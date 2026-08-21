--
-- Phase 4 — Predict layer.
--
-- Scenarios mirror colyseus-0.18 PORTING/generate-predict-fixtures.cts
-- (self-verified against the JS reference). Contract:
-- PORTING/sdk-ports-predict-layer.md.
--
local Decoder = require 'colyseus.serializer.schema.decoder'
local get_callbacks = require 'colyseus.serializer.schema.callbacks'
local InputEncoder = require 'colyseus.serializer.schema.input_encoder'
local InputHandle = require 'colyseus.input_handle'
local RoomClock = require 'colyseus.room_clock'
local Predict = require 'colyseus.predict.predict'
local Reconciler = require 'colyseus.predict.reconciler'
local PredictedEventChannel = require 'colyseus.predict.predicted_event_channel'
local PredictedSpawns = require 'colyseus.predict.predicted_spawns'

return function()
  local ReconState = require 'test.schema.Predict.ReconState'
  local AccelInput = require 'test.schema.Predict.AccelInput'
  local PassiveEnt = require 'test.schema.Predict.PassiveEnt'
  local ReckonBall = require 'test.schema.Predict.ReckonBall'

  local function stub_connection()
    local stub = { state = "OPEN", sent = {} }
    function stub:send(data) table.insert(self.sent, data) end
    return stub
  end

  local function make_handle(command)
    local encoder = InputEncoder.new(command)
    local stub = stub_connection()
    return InputHandle.new(command, encoder, {},
      function() return stub end, function() return nil end)
  end

  local function assert_close(expected, actual, epsilon)
    if math.abs(expected - actual) > (epsilon or 1e-9) then
      error(("assert_close failed: expected %s, got %s"):format(
        tostring(expected), tostring(actual)), 2)
    end
  end

  --- Pin offset 0: one no-rtt sample at NOW == s_now makes
  --- server_now() == RoomClock.get_now().
  local function synced_clock(s_now)
    local clock = RoomClock.new()
    clock:sample(s_now, -1)
    return clock
  end

  --- Listener stub — tests push samples directly, no decoder bytes.
  local function fake_callbacks()
    local listeners = {}
    local cb = {}
    function cb:listen(instance, field, handler, immediate)
      listeners[field] = handler
      if immediate then handler(instance[field]) end
      return function() listeners[field] = nil end
    end
    function cb:push(field, value) listeners[field](value) end
    return cb
  end

  --- Listener stub for the attach_all path: keyed per instance, and it hands
  --- back the on_add handler so a test can add children itself.
  local function collection_callbacks()
    local adds, listeners = {}, {}
    local cb = {}
    function cb:listen(instance, field, handler, immediate)
      local per = listeners[instance]
      if per == nil then per = {}; listeners[instance] = per end
      per[field] = handler
      if immediate then handler(instance[field]) end
      return function() per[field] = nil end
    end
    function cb:on_add(collection, handler, _immediate)
      adds[collection] = handler
      return function() adds[collection] = nil end
    end
    function cb:on_remove(_collection, _handler) return function() end end
    function cb:add(collection, child, key) adds[collection](child, key) end
    function cb:push(instance, field, value) listeners[instance][field](value) end
    return cb
  end

  local function lerp_setup(x0)
    local ent = { __refid = 1, a = x0 or 10 }
    local cb = fake_callbacks()
    local predict = Predict.new(cb, RoomClock.new())
    return ent, cb, predict
  end

  describe("predict layer", function()

    it("ReconcilerCore", function()
      local NOW = 0
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local truth = ReconState:new()
        truth.x = 0
        truth.vx = 0
        local command = AccelInput:new()
        command.ax = 0
        local handle = make_handle(command)
        local me = Reconciler.new(truth, {
          input = handle,
          fields = { "x", "vx" },
          step = function(ctx, s, cmd)
            s.vx = s.vx + cmd.ax * ctx.dt
            s.x = s.x + s.vx * ctx.dt
          end,
          smooth_ms = 0,
          step_ms = 50,
        })

        -- server mirror: the SAME deterministic step applied to truth
        local function server_step(ax)
          truth.vx = truth.vx + ax * 0.05
          truth.x = truth.x + truth.vx * 0.05
        end

        -- fixture trajectory (f64 bit-exact vs the JS reference)
        local expected_x = { 0.025, 0.07500000000000001, 0.15000000000000002,
          0.21250000000000002, 0.2625, 0.30000000000000004 }
        local expected_vx = { 0.5, 1, 1.5, 1.25, 1, 0.75 }

        NOW = 0; me:tick(NOW)
        local sent = {}
        for i = 1, 6 do
          NOW = i * 50; me:tick(NOW)
          local ax = (i <= 3) and 10 or -5
          sent[i] = ax
          command.ax = ax
          handle:send()
          assert_equal(expected_x[i], me.state.x)
          assert_equal(expected_vx[i], me.state.vx)
          if i >= 3 then
            -- trailing ack: server processed input i-2
            server_step(sent[i - 2])
            handle:ack_input(i - 2)
            me:tick(NOW)
          end
          assert_equal(0, me.last_correction_mag)
        end
        assert_equal(4, me.reconcile_seq)
        assert_equal(0.75, me.state.vx)

        -- divergent truth: server-side teleport the client didn't predict
        server_step(sent[4])
        truth.x = truth.x + 100
        handle:ack_input(5)
        NOW = 350; me:tick(NOW)
        assert_close(100, me.last_correction_mag)
        assert_close(-100, me.last_correction.x)
        assert_close(100.3, me.state.x)
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    it("ReconcilerMemoEpoch", function()
      local NOW = 0
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local truth = ReconState:new()
        truth.x = 0
        local command = AccelInput:new()
        command.ax = 0
        local handle = make_handle(command)
        local compute_runs = 0
        local me = Reconciler.new(truth, {
          input = handle,
          fields = { "x" },
          step = function(ctx, s, cmd)
            -- memo: computed once live, frozen on replay
            local bonus = ctx:memo(function()
              compute_runs = compute_runs + 1
              if cmd.ax >= 2 then return 5 end
              return nil
            end)
            s.x = s.x + cmd.ax + (bonus or 0)
          end,
          smooth_ms = 0,
          step_ms = 50,
        })

        NOW = 0; me:tick(NOW)
        command.ax = 1; handle:send()
        command.ax = 2; handle:send()   -- memoizes 5
        command.ax = 1; handle:send()
        assert_equal(9, me.state.x)
        assert_equal(3, compute_runs)

        -- ack 1 with matching truth -> adopt + replay 2..3; memo frozen
        truth.x = 1
        handle:ack_input(1)
        NOW = 50; me:tick(NOW)
        assert_equal(9, me.state.x)
        assert_equal(3, compute_runs)

        -- epoch follow: handle reset -> controller self-resets from truth
        truth.x = 42
        handle:reset()
        NOW = 100; me:tick(NOW)
        assert_equal(42, me.state.x)
        assert_equal(0, me:pending_count())
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    it("PassiveSmoothing", function()
      local NOW = 0
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local state = PassiveEnt:new()
        local decoder = Decoder:new(state)
        local callbacks = get_callbacks(decoder)
        local clock = RoomClock.new()
        clock:set_patch_interval(50)
        local predict = Predict.new(callbacks, clock)
        local ent = decoder.state

        predict:track(ent, "a", { mode = "lerp" })
        predict:track(ent, "b", { mode = "damped" })
        predict:track(ent, "c", { mode = "extrapolate", smooth_ms = 0 })
        predict:track(ent, "d", { mode = "raw" })
        predict:track(ent, "yaw", { mode = "lerp", angle = true })

        local function patch(s_now, bytes)
          NOW = s_now
          clock:sample(s_now, -1)   -- offset 0 -> server_now == NOW
          decoder:decode(bytes)
        end

        patch(1000, { 128, 10, 129, 10, 130, 10, 131, 10, 132, 3 })
        patch(1050, { 128, 20, 129, 20, 130, 20, 131, 20, 132, 253 }) -- yaw -3 (±π seam)
        patch(1100, { 128, 30, 129, 30, 130, 30, 131, 30 })

        -- fixture reads @1150: lerp(a)=20, raw(d)=30, extrapolate(c)=40
        NOW = 1150; predict:tick(NOW)
        assert_equal(20, predict:value(ent, "a"))
        assert_equal(30, predict:value(ent, "d"))
        assert_equal(40, predict:value(ent, "c"))
        -- angle unwrap kept the read on the ±π seam (no glide through 0)
        assert_equal(true, math.abs(predict:value(ent, "yaw")) > 3)

        NOW = 1175; predict:tick(NOW)
        assert_equal(25, predict:value(ent, "a"))
        assert_equal(45, predict:value(ent, "c"))

        -- idle-resume gap collapse: a idle 1100->1400 then 40; synthetic
        -- held sample (1350, 30) -> 31 / 35 / 40
        patch(1400, { 128, 40 })
        NOW = 1455; predict:tick(NOW)
        assert_equal(31, predict:value(ent, "a"))
        NOW = 1475; predict:tick(NOW)
        assert_equal(35, predict:value(ent, "a"))
        NOW = 1500; predict:tick(NOW)
        assert_equal(40, predict:value(ent, "a"))
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    it("TickDefaultsToTheClock", function()
      local NOW = 0
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local decoder = Decoder:new(PassiveEnt:new())
        local predict = Predict.new(get_callbacks(decoder), RoomClock.new())
        predict:_adopt_fixed_step(50)

        -- The render time is what pins `now` to an axis; the send budget only
        -- sees deltas, so a constant offset would cancel out of it unnoticed.
        NOW = 1234
        assert_equal(0, predict:tick())        -- first frame has no delta
        assert_equal(1234, predict._render_time)

        NOW = 1334
        assert_equal(2, predict:tick())        -- 100ms of a 50ms step
        assert_equal(1334, predict._render_time)
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    it("ReckonValueAt", function()
      local NOW = 0
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local state = ReckonBall:new()
        local decoder = Decoder:new(state)
        local callbacks = get_callbacks(decoder)
        local clock = RoomClock.new()
        local predict = Predict.new(callbacks, clock)
        local ball = decoder.state

        predict:track_reckon(ball, {
          fields = { "x" },
          step = function(s, dt, _elapsed) s.x = s.x + s.vx * dt end,
          smooth_ms = 0,   -- raw projection
          substep = 10,
        })

        -- patch: x=100 vx=50 stamped s_now=1000 (offset 0 -> server_now == NOW)
        NOW = 1000
        clock:sample(1000, -1)
        decoder:decode({ 128, 100, 129, 50 })

        -- fixture: 1000->100, 1050->102.5, 1100->105, 1200->110
        local traj = { { 1000, 100 }, { 1050, 102.5 }, { 1100, 105 }, { 1200, 110 } }
        for _, pair in ipairs(traj) do
          NOW = pair[1]
          predict:tick(NOW)
          assert_close(pair[2], predict:value(ball, "x"))
        end

        -- value_at: arbitrary instant raw; the past clamps to the snapshot
        assert_close(107.5, predict:value_at(ball, "x", 1150))
        assert_close(100, predict:value_at(ball, "x", 900))
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    -- Lerp + smooth_ms — the display-only output spring on the lerp result
    -- (mirror of sdk test/predict-lerp-smoothing.test.ts). Default 0 (off):
    -- the output stays the raw interpolant, bit-identical to a spring-less
    -- lerp. Armed, it keeps rendered velocity continuous, trailing the raw
    -- output by speed * smooth_ms during motion — frame-rate independently.

    it("LerpSmoothMsDefaultOff", function()
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        -- the GOTCHA this guards: 50 is the damped/extrapolate default —
        -- lerp must NOT silently spring with it
        local ent1, cb1, p1 = lerp_setup()
        local ent2, cb2, p2 = lerp_setup()
        p1:attach(ent1, { a = "lerp" })
        p2:attach(ent2, { a = { mode = "lerp", smooth_ms = 0 } })

        NOW = 1050; cb1:push("a", 20); cb2:push("a", 20)
        NOW = 1130; p1:tick(NOW); p2:tick(NOW)   -- target 1030 -> u = 0.6
        local v = p1:value(ent1, "a")
        assert_close(16, v, 1e-12)
        assert_equal(v, p2:value(ent2, "a"))

        NOW = 1145; cb1:push("a", 35); cb2:push("a", 35)
        NOW = 1170; p1:tick(NOW); p2:tick(NOW)
        assert_equal(p2:value(ent2, "a"), p1:value(ent1, "a"))
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    it("LerpSmoothMsTrailsRaw", function()
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local ent_r, cb_r, p_r = lerp_setup()
        local ent_s, cb_s, p_s = lerp_setup()
        p_r:attach(ent_r, { a = "lerp" })
        p_s:attach(ent_s, { a = { mode = "lerp", smooth_ms = 30 } })

        for t = 1050, 1400, 50 do
          NOW = t
          local x = 10 + (t - 1000) / 5
          cb_r:push("a", x); cb_s:push("a", x)
        end
        for t = 1000, 1400, 10 do
          NOW = t
          p_r:tick(t); p_s:tick(t)
          p_r:value(ent_r, "a"); p_s:value(ent_s, "a")
        end
        local v_raw = p_r:value(ent_r, "a")
        local v_sm = p_s:value(ent_s, "a")
        assert_equal(true, v_raw > 10)          -- raw is moving
        assert_equal(true, v_sm < v_raw)        -- spring trails the raw output
        assert_equal(true, v_sm > v_raw - 15)   -- bounded, not stuck
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    it("LerpSmoothMsFrameRateIndependent", function()
      -- 200 u/s stream, smooth_ms 25 -> trail = 200 * 0.025 = 5 u; the exact
      -- first-order-hold step holds it at ANY tick cadence
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local function run(tick_ms)
          NOW = 1000
          local ent, cb, p = lerp_setup()
          p:attach(ent, { a = { mode = "lerp", smooth_ms = 25 } })
          local v = 10
          for t = 1000 + tick_ms, 2500, tick_ms do
            NOW = t
            if t % 50 == 0 then cb:push("a", 10 + (t - 1000) / 5) end
            p:tick(t)
            v = p:value(ent, "a")
          end
          local raw_at_2500 = 10 + (2500 - 100 - 1000) / 5   -- target = now - delay(100)
          return raw_at_2500 - v
        end
        local trail_fine = run(10)
        local trail_coarse = run(25)
        assert_close(5, trail_fine, 1e-6)
        assert_close(5, trail_coarse, 1e-6)
        assert_equal(true, math.abs(trail_fine - trail_coarse) <= 1e-6)
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    it("LerpSmoothMsSnapPops", function()
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local ent, cb, p = lerp_setup()
        p:attach(ent, { a = { mode = "lerp", snap = 4, smooth_ms = 30 } })

        NOW = 1050; cb:push("a", 10.2)   -- establish cadence
        NOW = 3000; cb:push("a", 60)     -- teleport
        NOW = 3060; p:tick(NOW)
        assert_equal(60, p:value(ent, "a"))   -- spring popped with the ring
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    it("DampedSmoothMsDefault50", function()
      -- lerp's 0 default must not leak into damped: unset smooth_ms chases
      -- with damped's own 50 default rather than freezing
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local ent, cb, p = lerp_setup()
        p:attach(ent, { a = "damped" })

        NOW = 1050; cb:push("a", 60)
        NOW = 1110; p:tick(NOW)
        local v = p:value(ent, "a")
        assert_equal(true, v > 10)   -- chasing
        assert_equal(true, v < 60)   -- still mid-glide
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    it("DampedSmoothMsZeroSnaps", function()
      -- the old rate-form 0 froze the output — 0 now means snap
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local ent, cb, p = lerp_setup()
        p:attach(ent, { a = { mode = "damped", smooth_ms = 0 } })

        NOW = 1050; cb:push("a", 60)
        NOW = 1110; p:tick(NOW)
        assert_equal(60, p:value(ent, "a"))
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    it("LerpSmoothMsSameFrameReRead", function()
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local ent, cb, p = lerp_setup()
        p:attach(ent, { a = { mode = "lerp", smooth_ms = 30 } })

        NOW = 1050; cb:push("a", 20)
        NOW = 1130; p:tick(NOW)
        local v1 = p:value(ent, "a")
        assert_equal(v1, p:value(ent, "a"))   -- spring advances once per frame
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    --- The JS-shaped config: one mode + opts shared across a `fields` list.
    --- It used to name no field the loop recognised, so attach tracked NOTHING
    --- and every read silently fell through to the raw instance.
    it("AttachSharedFieldsConfig", function()
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local shared_ent = { __refid = 1, x = 10, y = 20 }
        local shared_cb = fake_callbacks()
        local shared = Predict.new(shared_cb, RoomClock.new())
        shared:attach(shared_ent, { mode = "lerp", fields = { "x", "y" } })

        -- the same thing said the other way, as the equality oracle
        local per_ent = { __refid = 1, x = 10, y = 20 }
        local per_cb = fake_callbacks()
        local per = Predict.new(per_cb, RoomClock.new())
        per:attach(per_ent, { x = { mode = "lerp" }, y = { mode = "lerp" } })

        NOW = 1050
        shared_cb:push("x", 20); shared_cb:push("y", 40)
        per_cb:push("x", 20); per_cb:push("y", 40)

        NOW = 1130; shared:tick(NOW); per:tick(NOW)   -- target 1030 -> u = 0.6
        assert_close(16, shared:value(shared_ent, "x"), 1e-12)
        assert_close(32, shared:value(shared_ent, "y"), 1e-12)
        assert_equal(per:value(per_ent, "x"), shared:value(shared_ent, "x"))
        assert_equal(per:value(per_ent, "y"), shared:value(shared_ent, "y"))
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    --- Options next to `mode` are the field opts, not decoration.
    it("AttachSharedFieldsCarriesOpts", function()
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local ent = { __refid = 1, x = 10 }
        local cb = fake_callbacks()
        local p = Predict.new(cb, RoomClock.new())
        -- delay 130 (not the 100 default) puts the render target on the FIRST
        -- sample, so the default would read 16 here
        p:attach(ent, { mode = "lerp", fields = { "x" }, delay = 130 })

        NOW = 1050; cb:push("x", 20)
        NOW = 1130; p:tick(NOW)
        assert_close(10, p:value(ent, "x"), 1e-12)
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    --- Same drop rule as the per-field shape: a `fields` entry the instance
    --- doesn't declare is skipped, so one config covers a mixed collection.
    it("AttachSharedFieldsDropsUnknown", function()
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local ent = { __refid = 1, x = 10 }
        local cb = fake_callbacks()
        local p = Predict.new(cb, RoomClock.new())
        p:attach(ent, { mode = "lerp", fields = { "x", "z" } })

        NOW = 1050; cb:push("x", 20)
        NOW = 1130; p:tick(NOW)
        assert_close(16, p:value(ent, "x"), 1e-12)
        assert_equal(0, p:value(ent, "z"))     -- no slot -> raw fallback
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    --- Attaching before the first patch is the normal case (join, then wire up),
    --- and a schema instance reads nil on every field until one lands — so the
    --- "does it declare this?" gate cannot be a value check.
    it("AttachBeforeFirstPatch", function()
      local NOW = 0
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local decoder = Decoder:new(PassiveEnt:new())
        local clock = RoomClock.new()
        local predict = Predict.new(get_callbacks(decoder), clock)
        local ent = decoder.state
        assert_nil(ent.a)                        -- nothing has arrived yet
        predict:attach(ent, { a = { mode = "lerp" } })

        NOW = 1000; clock:sample(1000, -1); decoder:decode({ 128, 10 })
        NOW = 1050; clock:sample(1050, -1); decoder:decode({ 128, 20 })
        NOW = 1130; predict:tick(NOW)            -- target 1030 -> u = 0.6
        assert_close(16, predict:value(ent, "a"), 1e-12)
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    --- attach_all hands the config to every child, so the shape has to survive
    --- the trip.
    it("AttachAllSharedFieldsConfig", function()
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local cb = collection_callbacks()
        local p = Predict.new(cb, RoomClock.new())
        p:attach_all("players", { mode = "lerp", fields = { "x", "y" } })

        local a = { __refid = 1, x = 10, y = 20 }
        local b = { __refid = 2, x = 0, y = 0 }
        cb:add("players", a, "a")
        cb:add("players", b, "b")

        NOW = 1050
        cb:push(a, "x", 20); cb:push(a, "y", 40)
        cb:push(b, "x", 10); cb:push(b, "y", 10)

        NOW = 1130; p:tick(NOW)                      -- target 1030 -> u = 0.6
        assert_close(16, p:value(a, "x"), 1e-12)
        assert_close(32, p:value(a, "y"), 1e-12)
        assert_close(6, p:value(b, "x"), 1e-12)
        assert_close(6, p:value(b, "y"), 1e-12)
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    --- A config of nothing but option keys can never track anything, so it is
    --- a mistake rather than a heterogeneous-collection miss: say so, once.
    it("AttachConfigNamesNoField", function()
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local original_print = print
      local said = {}
      print = function(msg) table.insert(said, msg) end
      local ok, err = pcall(function()
        local cb = collection_callbacks()
        local p = Predict.new(cb, RoomClock.new())

        local broken = { mode = "lerp", delay = 100 }
        p:attach_all("players", broken)
        local a = { __refid = 1, x = 10 }
        local b = { __refid = 2, x = 10 }
        cb:add("players", a, "a")
        cb:add("players", b, "b")

        assert_equal(1, #said)                 -- once per config, not per child
        assert_equal(10, p:value(a, "x"))      -- nothing tracked -> raw fallback

        p:attach(a, { fields = {} })           -- an empty list is just as empty
        assert_equal(2, #said)
      end)
      print = original_print
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    it("EventChannelSettlement", function()
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local clock = synced_clock(1000)

        local log = {}
        local unpredicted = 0
        local chan = PredictedEventChannel.new({
          on_predict = function(p) table.insert(log, "P:" .. p) end,
          on_confirm = function(p) table.insert(log, "C:" .. p) end,
          on_reject = function(p) table.insert(log, "R:" .. p) end,
          on_unpredicted = function(_key) unpredicted = unpredicted + 1 end,
          grace_ticks = 3,
        }, clock)

        chan:predict("goal-a")
        assert_equal(1, chan:pending_count())
        assert_equal(1, chan:confirm("goal-a"))
        assert_equal(0, chan:confirm("goal-b"))
        assert_equal(1, unpredicted)

        -- pending dedupe
        chan:predict("kill-1")
        chan:predict("kill-1")
        assert_equal(1, chan:pending_count())

        -- sim-born entry with grace auto-reject
        local acked = 10
        chan:_predict_from_sim(12, "kill-2", function() return acked end)
        assert_equal(2, chan:pending_count())
        acked = 14
        chan:prune()
        assert_equal(true, chan:has("kill-2"))
        acked = 15   -- >= 12 + 3 -> auto-reject
        chan:prune()
        assert_equal(false, chan:has("kill-2"))

        -- UI-born TTL: rtt 0 -> 600ms
        NOW = 1601
        chan:prune()
        assert_equal(0, chan:pending_count())

        assert_equal("P:goal-a|C:goal-a|P:kill-1|P:kill-2|R:kill-2|R:kill-1",
          table.concat(log, "|"))
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

    it("SpawnsCorrelation", function()
      local NOW = 1000
      local original_now = RoomClock.get_now
      RoomClock.get_now = function() return NOW end
      local ok, err = pcall(function()
        local clock = synced_clock(1000)

        local rejected = {}
        local store = PredictedSpawns.new({
          owned = function(s) return s.owner == "me" end,
          spawn_time = function(s) return s.born_ms end,
          step = function(l, dt) l[1] = l[1] + 10 * dt end,
          on_reject = function(_l, id) table.insert(rejected, id) end,
        }, clock)

        local local_rocket = { 0 }
        local h1 = store:spawn(local_rocket)
        assert_equal(1, h1.id)

        -- pending local steps on the serverNow axis: 1000->1100 = dt 0.1 -> +1
        store:tick(0)
        NOW = 1100
        store:tick(0)
        assert_close(1, local_rocket[1])

        -- fifo match + lead = born_ms - at = 1080 - 1000
        local server1 = { owner = "me", born_ms = 1080 }
        store:handle_add(server1)
        local e1 = store:entry_for(server1)
        assert_equal(1, e1.id)
        assert_equal(true, e1.confirmed)
        assert_equal(80, e1.lead_ms)

        -- foreign entity: never consumes a prediction
        local server2 = { owner = "them", born_ms = 1090 }
        store:handle_add(server2)
        assert_equal(0, store:entry_for(server2).lead_ms)
        assert_equal(nil, store:entry_for(server2).local_state)

        -- mispredict prune: unmatched pending, TTL 600
        local h2 = store:spawn({ 0 })
        NOW = 1701
        store:prune()
        assert_equal(1, #rejected)
        assert_equal(h2.id, rejected[1])
        assert_equal(false, store:alive(h2.id))

        -- remove drops the confirmed entry
        store:handle_remove(server1)
        assert_equal(false, store:alive(1))
        assert_equal(1, store:size())
      end)
      RoomClock.get_now = original_now
      if not ok then error(err, 0) end
    end)

  end)
end
