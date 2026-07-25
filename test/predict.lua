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
          smoothing = 0,
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
          smoothing = 0,
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
        predict:track(ent, "c", { mode = "extrapolate", damping = 0 })
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
          smoothing = 0,   -- raw projection
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
