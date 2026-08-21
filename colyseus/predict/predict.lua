--
-- Predict — passive smoothing of the server stream for entities you DON'T
-- control (port of the JS SDK's predict/Predictor.ts: passive engine +
-- orchestration). One read idiom: predict:value(instance, field) — with raw
-- instance fallback when untracked. Reconciler factories inject the room
-- clock and adopt the fixed step for tick()'s send budget.
--
-- Modes: "lerp" (render-delay target, hold-never-extrapolate), "extrapolate"
-- (2-step lookback slope + EMA), "damped" (EMA chase), "raw" (latest sample),
-- "reckon" (dead-reckon via a step shared with the server).
--
local RoomClock = require 'colyseus.room_clock'
local Reconciler = require 'colyseus.predict.reconciler'
local PredictedEventChannel = require 'colyseus.predict.predicted_event_channel'
local PredictedSpawns = require 'colyseus.predict.predicted_spawns'
local SimReconciler = require 'colyseus.predict.sim_reconciler'
local get_callbacks = require 'colyseus.serializer.schema.callbacks'

local Predict = {}
Predict.__index = Predict

local RING_CAP = 16
local GAP_RESUME_MULT = 3
local GAP_RESUME_PATCH_MULT = 1.5
local GAP_RESUME_MAX_MS = 250
local MAX_STEPS_PER_FRAME = 5

local FIELD_DEFAULTS = {
  mode = "lerp",
  delay = 100,            -- lerp render-time lag (ms)
  max_extrapolate = 200,  -- extrapolate overshoot cap (ms)
  tick_interval = 0,      -- arrival-grid snap (ms); 0 off
  snap = 0,               -- value-space teleport threshold; 0 off
  angle = false,          -- radian angle — unwrap samples over the shortest arc
}

-- smooth_ms fallback for damped/extrapolate (lerp's output spring defaults 0)
local DEFAULT_SMOOTH_MS = 50

local function resolve_field_opts(options)
  local opts = {}
  for k, v in pairs(FIELD_DEFAULTS) do
    if options ~= nil and options[k] ~= nil then
      opts[k] = options[k]
    else
      opts[k] = v
    end
  end
  -- smooth_ms (time constant, ms; 0 = off/snap) has no shared default: nil
  -- resolves per mode at the read site — 50 on damped/extrapolate, 0 on lerp
  if options ~= nil then opts.smooth_ms = options.smooth_ms end
  return opts
end

local function to_number(value)
  local t = type(value)
  if t == "number" then return value end
  if t == "boolean" then return value and 1 or 0 end
  return 0
end

---@param callbacks table the SDK callbacks object (from
---  `require('colyseus.serializer.schema.callbacks')(room_or_decoder)`)
---@param clock table RoomClock (the room's clock)
--- The one-liner every caller wants: a Predict over a room's callbacks and
--- clock. `Predict.new(get_callbacks(room), room.clock)` is the same two
--- collaborators every time and no decision the caller is better placed to make.
function Predict.get(room)
  return Predict.new(get_callbacks(room), room.clock)
end

function Predict.new(callbacks, clock)
  local self = setmetatable({}, Predict)
  self._callbacks = callbacks
  self._clock = clock
  self._render_time = 0
  self._slots_by_ref = {}   -- refid -> field -> slot
  self._sims_by_ref = {}    -- refid -> reckon sim state
  self._driven = {}
  self._attachments = {}    -- every attach_all* detacher, so dispose can undo them
  self._warned_configs = setmetatable({}, { __mode = "k" })
  self._fixed_step_ms = nil -- adopted from the first reconciler
  self._step_acc = 0
  self._last_frame_now = -1
  return self
end

-- --- Attach ---------------------------------------------------------------

-- Keys that configure the attach itself rather than name a field. Used ONLY to
-- recognise a config that names no field at all — the per-field shape still
-- tries every key against the instance, so a schema field called `snap` keeps
-- working.
local CONFIG_KEYS = {
  mode = true, fields = true, step = true, substep = true,
  delay = true, max_extrapolate = true, tick_interval = true,
  snap = true, smooth_ms = true, angle = true,
}

--- True when `config` names at least one candidate field, in either shape.
local function names_a_field(config)
  if config.fields ~= nil then return #config.fields > 0 end
  for key in pairs(config) do
    if not CONFIG_KEYS[key] then return true end
  end
  return false
end

local function noop() end

---@private
--- Track one numeric field for smoothing. Returns an untrack function.
--- Internal primitive under :attach() — see PORTING.md, which strips
--- track/untrack/trackStepped from the published surface.
function Predict:_track(instance, field, options)
  local opts = resolve_field_opts(options)
  local refid = instance.__refid
  local per_ref = self._slots_by_ref[refid]
  if per_ref == nil then
    per_ref = {}
    self._slots_by_ref[refid] = per_ref
  end
  -- idempotent per field
  local existing = per_ref[field]
  if existing ~= nil then
    if existing.detach ~= nil then existing.detach() end
    per_ref[field] = nil
  end

  local initial = to_number(instance[field])
  local slot = {
    field = field,
    instance = instance,
    opts = opts,
    v1 = initial,
    aux_v = initial,
    aux_t = RoomClock.get_now(),
    lerp_prev = initial,  -- previous frame's RAW lerp output (the spring's FOH slope)
    ring_t = {},
    ring_v = {},
    ring_head = 0,   -- 0-based; access via ring_t[phys + 1]
    ring_count = 0,
  }
  per_ref[field] = slot

  slot.detach = self._callbacks:listen(instance, field, function(current, _previous)
    self:_on_sample(slot, to_number(current))
  end, true)
  return function() self:untrack(instance, field) end
end

---@private
--- Dead-reckon fields of an instance with a step SHARED with the server.
--- Internal primitive under :attach({ mode = "reckon", ... }) — named for the
--- reference's `trackStepped`, and stripped from the published surface there.
---@param opts table {fields, step = fun(scratch, dt_seconds, elapsed_ms),
---  smooth_ms = 50 (0 = raw projection), substep = 16 (ms), snap = 0}
function Predict:_track_stepped(instance, opts)
  local refid = instance.__refid
  local scratch = getmetatable(instance):new()
  local copy_fields = {}
  for _, f in ipairs(instance._fields_by_index) do
    local ft = instance._schema[f]
    -- Every primitive, strings included: the scratch is documented as a FULL
    -- copy of the entity so the shared step can read descriptors it never
    -- attached (a bot's `kind`). Dropping strings makes step functions that
    -- branch on one silently take the default branch — and attach_all_reckon
    -- gives the caller no live instance to fall back on.
    if type(ft) == "string" then
      table.insert(copy_fields, f)
    elseif type(ft) == "table" and ft.quantized ~= nil then
      table.insert(copy_fields, f)
    end
  end
  local n = #opts.fields
  local sim = {
    instance = instance,
    scratch = scratch,
    fields = opts.fields,
    step = opts.step,
    smooth_ms = opts.smooth_ms or 50,
    substep = (opts.substep ~= nil and opts.substep > 0) and opts.substep or 16,
    snap = opts.snap or 0,
    smoothed = {},
    out = {},
    value_out = {},
    offset = {},
    out_prev = {},
    frame_vel = {},
    last_base_t = nil,
    last_apply_time = nil,
    copy_fields = copy_fields,
    forward_ms = nil, -- per-entity horizon override (spawns lead)
  }
  for k = 1, n do
    sim.smoothed[k] = to_number(instance[opts.fields[k]])
    sim.out[k] = 0
    sim.value_out[k] = 0
    sim.offset[k] = 0
    sim.out_prev[k] = 0
    sim.frame_vel[k] = 0
  end
  self._sims_by_ref[refid] = sim

  -- each reckoned field gets a RECKON slot (sample mirror + fallback)
  local offs = {}
  for _, f in ipairs(opts.fields) do
    table.insert(offs, self:_track(instance, f, { mode = "reckon" }))
  end
  return function()
    for _, off in ipairs(offs) do off() end
    self._sims_by_ref[refid] = nil
  end
end

--- Per-instance forward-horizon override (the spawns store's lead reckon).
function Predict:_bind_forward(instance, forward_ms)
  local sim = self._sims_by_ref[instance.__refid]
  if sim ~= nil then sim.forward_ms = forward_ms end
end

function Predict:untrack(instance, field)
  local refid = instance.__refid
  local per_ref = self._slots_by_ref[refid]
  if per_ref == nil then return end
  local slot = per_ref[field]
  if slot ~= nil then
    if slot.detach ~= nil then slot.detach() end
    per_ref[field] = nil
    if next(per_ref) == nil then self._slots_by_ref[refid] = nil end
  end
end

--- Stop tracking every field (and any reckon sim) of an instance.
function Predict:detach(instance)
  local refid = instance.__refid
  local per_ref = self._slots_by_ref[refid]
  if per_ref ~= nil then
    for _, slot in pairs(per_ref) do
      if slot.detach ~= nil then slot.detach() end
    end
    self._slots_by_ref[refid] = nil
  end
  self._sims_by_ref[refid] = nil
end

--- Attach prediction to ONE instance from a declarative config. Returns a
--- detacher.
---
--- Three shapes, mirroring the reference:
---
---   -- per-field smoothing; each field picks its own mode
---   predict:attach(boss, { x = "lerp", y = "lerp",
---                          yaw = { mode = "damped", angle = true } })
---
---   -- one mode and its options shared across `fields`
---   predict:attach(boss, { mode = "lerp", fields = { "x", "y" }, delay = 100 })
---
---   -- dead reckoning, one step shared with the server across `fields`
---   predict:attach(bot, { mode = "reckon", fields = { "x", "y" }, step = patrol })
---
--- Fields the instance's schema doesn't declare are DROPPED, not an error:
--- one config can cover a heterogeneous collection, and a field that isn't
--- there would otherwise subscribe to nothing (or, in the reckon scratch, read
--- garbage).
function Predict:attach(instance, config)
  if not names_a_field(config) then
    self:_warn_empty_config(config)
    return noop
  end
  if config.mode == "reckon" then
    return self:_track_stepped(instance, config)
  end
  local offs = {}
  if config.fields ~= nil then
    -- shared shape: `config` is itself the per-field opts (`fields` is inert
    -- to resolve_field_opts, so there is nothing to strip)
    for _, field in ipairs(config.fields) do
      if instance[field] ~= nil then
        table.insert(offs, self:_track(instance, field, config))
      end
    end
  else
    for field, spec in pairs(config) do
      if instance[field] ~= nil then
        local opts = (type(spec) == "string") and { mode = spec } or spec
        table.insert(offs, self:_track(instance, field, opts))
      end
    end
  end
  return function()
    for _, off in ipairs(offs) do off() end
  end
end

---@private
--- A config of nothing but option keys tracks nothing whatever the instance
--- looks like, so it is a mistake, not a heterogeneous-collection miss. Warned
--- once per config table — attach_all would otherwise print it per child.
function Predict:_warn_empty_config(config)
  if self._warned_configs[config] then return end
  self._warned_configs[config] = true
  print("colyseus.predict: attach config names no field, so nothing was " ..
    "attached. List them under `fields` ({ mode = \"lerp\", fields = " ..
    "{ \"x\", \"y\" } }) or key the config by field name ({ x = \"lerp\" }).")
end

--- Attach prediction to every child of a root-level collection: wires
--- on_add -> attach(child, config) and on_remove -> detach. Same config shapes
--- as :attach(), reckon included — there is no separate reckon flavour.
---
---   predict:attach_all("players", { mode = "lerp", fields = { "x", "y" } })
function Predict:attach_all(collection, config)
  return self:_attach_each(collection, function(child)
    self:attach(child, config)
  end)
end

---@private
--- Shared add/remove wiring behind both attach_all flavours.
function Predict:_attach_each(collection, attach)
  local tracked = {}
  local add_off = self._callbacks:on_add(collection, function(child, _key)
    attach(child)
    table.insert(tracked, child)
  end, true)
  local remove_off = self._callbacks:on_remove(collection, function(child, _key)
    for i, c in ipairs(tracked) do
      if c == child then
        table.remove(tracked, i)
        break
      end
    end
    self:detach(child)
  end)
  local off = function()
    if add_off ~= nil then add_off() end
    if remove_off ~= nil then remove_off() end
    for _, child in ipairs(tracked) do self:detach(child) end
    tracked = {}
  end
  table.insert(self._attachments, off)
  return off
end

--- Release everything this Predict registered: tracked fields, reckon sims,
--- attach_all wiring and every driven child.
---
--- This matters more than it looks. Callbacks live on the ROOM, so a Predict
--- that outlives its owner keeps firing handlers into freed state — attach and
--- detach are not symmetric unless someone closes the loop, and the attach_all
--- detachers are held here, not by the caller. This is that loop; call it when
--- the screen using this goes away.
function Predict:dispose()
  for _, off in ipairs(self._attachments) do off() end
  self._attachments = {}
  self._slots_by_ref = {}
  self._sims_by_ref = {}
  for _, child in ipairs(self._driven) do
    if child.dispose ~= nil then child:dispose() end
  end
  self._driven = {}
  self._fixed_step_ms = nil
end

-- --- Factories ------------------------------------------------------------

--- Spawn a driven Reconciler (clock injected, fixed step adopted).
function Predict:reconciler(instance, opts)
  if opts.clock == nil then opts.clock = self._clock end
  self:_bind_render_delay(opts.input)
  local recon = Reconciler.new(instance, opts)
  self:_adopt_fixed_step(recon.step_ms)
  self:_install_bound_overlay(recon)
  table.insert(self._driven, recon)
  return recon
end

---@private
--- Route `value(instance, field)` at every field a controller predicts, so ONE
--- read idiom covers the whole render layer: passively-smoothed remotes and
--- controller-owned entities alike, with the caller never naming a pose key.
---
--- Any passive slot already on that field is STASHED, not dropped — its
--- listener keeps sampling, and dispose() puts it back.
function Predict:_install_bound_overlay(ctrl)
  if ctrl.bound_registrations == nil then return end
  local offs = {}
  for _, reg in ipairs(ctrl:bound_registrations()) do
    local refid = reg.source ~= nil and reg.source.__refid or nil
    if refid ~= nil then
      local per_ref = self._slots_by_ref[refid]
      if per_ref == nil then
        per_ref = {}
        self._slots_by_ref[refid] = per_ref
      end
      for k, field in ipairs(reg.fields) do
        local stash = per_ref[field]
        if stash ~= nil and stash.opts.mode == "bound" then
          print("colyseus.predict: '" .. field .. "' is already bound to a controller — " ..
            "the newer registration wins.")
          stash = stash.stash
        end
        per_ref[field] = {
          field = field,
          instance = reg.source,
          opts = { mode = "bound" },
          ctrl = ctrl,
          pose_key = reg.pose_keys[k],
          stash = stash,
        }
        table.insert(offs, { per_ref = per_ref, field = field })
      end
    end
  end
  if #offs > 0 then
    ctrl:on_disposed(function()
      for _, o in ipairs(offs) do
        local slot = o.per_ref[o.field]
        if slot ~= nil and slot.opts.mode == "bound" then
          o.per_ref[o.field] = slot.stash   -- nil when there was no passive slot
        end
      end
    end)
  end
end

---@private
--- Tell the input handle how far in the past this client draws, taken from the
--- lerp delay already attached here.
---
--- Worth doing automatically because the failure is silent and expensive: a
--- lag-compensating server rewinds to `server_now - (render_delay + rtt/2)`, so
--- leaving render_delay at zero makes every rewound read land one full
--- render-delay early, and shots miss by exactly that much with nothing in the
--- logs to say so. An explicit `render_delay` on room:input() still wins.
function Predict:_bind_render_delay(input)
  if input == nil or input:render_delay() > 0 then return end
  for _, per_ref in pairs(self._slots_by_ref) do
    for _, slot in pairs(per_ref) do
      local o = slot.opts
      if o ~= nil and o.mode == "lerp" and (o.delay or 0) > 0 then
        input:set_render_delay(o.delay)
        return
      end
    end
  end
end

--- Spawn a driven SimReconciler — the composite face, for a world of parts
--- rather than one entity's fields.
function Predict:sim(opts)
  if opts.clock == nil then opts.clock = self._clock end
  self:_bind_render_delay(opts.input)
  local recon = SimReconciler.new(opts)
  self:_adopt_fixed_step(recon.step_ms)
  self:_install_bound_overlay(recon)
  table.insert(self._driven, recon)
  return recon
end

--- Spawn a driven PredictedEventChannel.
function Predict:define_event(opts)
  local channel = PredictedEventChannel.new(opts, self._clock)
  table.insert(self._driven, channel)
  return channel
end

--- Spawn a driven PredictedSpawns store wired to a root-level collection's
--- add/remove stream.
---
--- With `fields`, the store also owns the collection's MOTION (no separate
--- attach_all needed): confirmed entities are dead-reckoned with the same
--- `step` that advances pending locals, and store:value(entry, field) is one
--- read path across the whole life of the entity.
---
---@param opts table PredictedSpawns opts plus optional reckon of the confirmed
---  entities: {fields, smooth_ms = 0, substep = 16}
function Predict:spawns(collection, opts)
  opts = opts or {}
  local store = PredictedSpawns.new(opts, self._clock)

  -- Reckon wiring (`fields` + `step`): every confirmed entity gets a reckon
  -- attach whose horizon is snapshot age PLUS the entry's measured input lead —
  -- 0 for a foreign entity (server-present, same as an attach_all reckon), the
  -- exact per-spawn uplink for an owned one (see spawn_time). An owned
  -- projectile thus keeps flying the shooter's timeline through the handoff.
  local reckon = (opts.fields ~= nil and opts.step ~= nil)
  local untrack = reckon and {} or nil
  local clock = self._clock

  local add_off = self._callbacks:on_add(collection, function(server, _key)
    store:handle_add(server)
    if not reckon or untrack[server] ~= nil then return end -- decoder re-fire
    -- AFTER handle_add: the lead is only measured once the entry collapses.
    local entry = store:entry_for(server)
    local lead = (entry ~= nil) and (entry.lead_ms or 0) or 0
    local off = self:_track_stepped(server, {
      fields = opts.fields,
      step = opts.step,
      -- 0, not the reckon default 50: a deterministic constant-step projectile
      -- rebases exactly, so smoothing here would only add lag.
      smooth_ms = opts.smooth_ms or 0,
      substep = opts.substep,
    })
    self:_bind_forward(server, function()
      if clock == nil then return math.max(0, lead) end
      local stamp = clock:last_server_time()
      local age = (stamp > 0) and math.max(0, clock:server_now() - stamp) or 0
      return math.max(0, age + lead)
    end)
    untrack[server] = off
  end, true)

  local remove_off = self._callbacks:on_remove(collection, function(server, _key)
    if untrack ~= nil then
      local off = untrack[server]
      if off ~= nil then off() end
      untrack[server] = nil
    end
    store:handle_remove(server)
  end)

  if reckon then
    -- route store:value() confirmed reads through the reckon slots
    store:bind_reader(function(server, field) return self:value(server, field) end)
  end

  store._on_disposed = function()
    if add_off ~= nil then add_off() end
    if remove_off ~= nil then remove_off() end
    if untrack ~= nil then
      for _, off in pairs(untrack) do off() end
      untrack = {}
    end
  end
  table.insert(self._driven, store)
  return store
end

function Predict:_adopt_fixed_step(step_ms)
  if self._fixed_step_ms == nil then
    self._fixed_step_ms = step_ms
    self._step_acc = 0
    self._last_frame_now = -1
    return
  end
  if math.abs(self._fixed_step_ms - step_ms) > 1e-6 then
    print("colyseus.predict: a reconciler's fixed step (" .. step_ms .. "ms) differs " ..
      "from this Predict's (" .. self._fixed_step_ms .. "ms). tick() paces one rate; " ..
      "use a separate Predict per rate.")
  end
end

-- --- Per-frame driver -----------------------------------------------------

--- Call once per render frame. Returns the SEND BUDGET: how many fixed input
--- steps are due — send exactly that many inputs, then read render values.
--- 0 until a reconciler advertises the step.
---@param now number|nil monotonic ms; omit to read the SDK clock, which is
--- what the JS reference does with its `performance.now()` default. Omitting
--- it keeps the caller off a platform clock of its own.
function Predict:tick(now)
  if now == nil then now = RoomClock.get_now() end
  self._render_time = now

  local steps = 0
  if self._fixed_step_ms ~= nil and self._fixed_step_ms > 0 then
    local dt = (self._last_frame_now < 0) and 0 or (now - self._last_frame_now)
    self._step_acc = self._step_acc + dt
    steps = math.floor(self._step_acc / self._fixed_step_ms)
    if steps > MAX_STEPS_PER_FRAME then
      -- hitch: drop the backlog instead of bursting
      self._step_acc = 0
      steps = MAX_STEPS_PER_FRAME
    else
      self._step_acc = self._step_acc - steps * self._fixed_step_ms
    end
  end
  self._last_frame_now = now

  -- drive children; compact the dead
  for i = #self._driven, 1, -1 do
    local child = self._driven[i]
    if child.dead then
      table.remove(self._driven, i)
    else
      child:tick(now)
      if child.prune ~= nil then child:prune() end
    end
  end
  return steps
end

-- --- Sample pipeline ------------------------------------------------------

function Predict:_on_sample(slot, current)
  local clock = self._clock
  local now
  if clock ~= nil and clock:last_server_time() > 0 then
    now = clock:last_server_time()  -- server-stamped, jitter-free
  else
    now = RoomClock.get_now()
  end

  local opts = slot.opts
  if opts.angle then
    -- unwrap onto the previous sample over the shortest arc
    local previous = slot.v1
    current = previous + math.atan2(math.sin(current - previous), math.cos(current - previous))
  end

  local head = slot.ring_head
  local count = slot.ring_count

  -- value-space teleport: clear history, pop (don't glide)
  if opts.snap > 0 and count > 0 and math.abs(current - slot.v1) > opts.snap then
    head = 0
    count = 0
    slot.aux_v = current
    slot.lerp_prev = current   -- lerp's output spring pops too
  end

  local last_t1 = nil
  if count > 0 then
    local h1 = (head == 0) and (RING_CAP - 1) or (head - 1)
    last_t1 = slot.ring_t[h1 + 1]
  end

  -- arrival-grid snap
  local snap_t = now
  if opts.tick_interval > 0 and last_t1 ~= nil then
    local elapsed = now - last_t1
    local ticks = (elapsed > 0) and math.max(1, math.floor(elapsed / opts.tick_interval + 0.5)) or 1
    snap_t = last_t1 + ticks * opts.tick_interval
    local cap = now + opts.tick_interval
    if snap_t > cap then snap_t = cap end
  end

  slot.v1 = current

  -- idle-resume gap collapse: inject a synthetic held sample so lerp resumes
  -- from "just before" instead of gliding across the whole idle gap
  if count >= 2 and last_t1 ~= nil then
    local h1 = (head == 0) and (RING_CAP - 1) or (head - 1)
    local h2 = (h1 == 0) and (RING_CAP - 1) or (h1 - 1)
    local last_interval = last_t1 - slot.ring_t[h2 + 1]
    local patch_ms = (clock ~= nil) and clock:patch_interval() or 0
    local span = (patch_ms > 0) and patch_ms or last_interval
    local trigger = (patch_ms > 0) and (GAP_RESUME_PATCH_MULT * patch_ms)
      or (GAP_RESUME_MULT * last_interval)
    if span > 0 and snap_t - last_t1 > trigger then
      local resume_span = math.min(span, GAP_RESUME_MAX_MS)
      slot.ring_t[head + 1] = snap_t - resume_span
      slot.ring_v[head + 1] = slot.ring_v[h1 + 1]
      head = (head + 1 >= RING_CAP) and 0 or (head + 1)
      if count < RING_CAP then count = count + 1 end
    end
  end

  slot.ring_t[head + 1] = snap_t
  slot.ring_v[head + 1] = current
  slot.ring_head = (head + 1 >= RING_CAP) and 0 or (head + 1)
  slot.ring_count = (count < RING_CAP) and (count + 1) or count
end

-- --- Reads ----------------------------------------------------------------

--- Smoothed/predicted RENDER value with raw instance fallback.
function Predict:value(instance, field)
  local per_ref = self._slots_by_ref[instance.__refid]
  local slot = per_ref ~= nil and per_ref[field] or nil
  if slot == nil then return to_number(instance[field]) end
  local mode = slot.opts.mode
  -- Controller-owned: a reconciler claimed this field, so the pose comes from
  -- its rollback rather than from a smoothing curve over the server stream.
  if mode == "bound" then return slot.ctrl:value(slot.pose_key) end
  if mode == "lerp" then return self:_compute_lerp(slot) end
  if mode == "damped" then return self:_compute_damped(slot) end
  if mode == "extrapolate" then return self:_compute_extrapolate(slot) end
  if mode == "reckon" then return self:_compute_reckon(slot) end
  return slot.v1 -- raw
end

--- RAW reckoned value at an arbitrary server-time instant (no smoothing
--- offset) — for game logic / lag-comp hit tests. Reckons forward from the
--- latest snapshot; the past clamps to it.
function Predict:value_at(instance, field, time)
  local per_ref = self._slots_by_ref[instance.__refid]
  local slot = per_ref ~= nil and per_ref[field] or nil
  if slot == nil or slot.opts.mode ~= "reckon" then
    return self:value(instance, field)
  end
  local sim = self._sims_by_ref[instance.__refid]
  if sim ~= nil then
    for k, f in ipairs(sim.fields) do
      if f == field then
        local base_t = (self._clock ~= nil) and self._clock:last_server_time() or nil
        local forward = (base_t ~= nil) and math.max(0, time - base_t) or 0
        self:_advance(sim, forward, sim.value_out, time)
        return sim.value_out[k]
      end
    end
  end
  return slot.v1
end

-- --- Mode computers -------------------------------------------------------

function Predict:_compute_damped(slot)
  local now = self._render_time
  local dt_frame = now - slot.aux_t
  slot.aux_t = now
  if dt_frame > 0 then
    local tau = slot.opts.smooth_ms or DEFAULT_SMOOTH_MS
    local k = (tau > 0) and (1 - math.exp(-dt_frame / tau)) or 1   -- 0 = snap
    slot.aux_v = slot.aux_v + (slot.v1 - slot.aux_v) * k
  end
  return slot.aux_v
end

function Predict:_compute_lerp(slot)
  local raw = self:_compute_lerp_raw(slot)
  local tau = slot.opts.smooth_ms or 0   -- lerp's output spring defaults OFF
  local now = self._render_time
  if tau <= 0 then
    -- Spring off (the default) — pin the state to the raw output so a
    -- runtime smooth_ms enable starts from here instead of gliding in
    -- from wherever the spring last rested.
    slot.aux_v = raw
    slot.lerp_prev = raw
    slot.aux_t = now
    return raw
  end
  local dt = now - slot.aux_t
  if dt <= 0 then return slot.aux_v end   -- same-frame re-read
  -- Exact first-order-hold step for a linearly-varying target (tau = smooth_ms):
  --   y(dt) = u1 - s*tau + (y0 - u0 + s*tau) * e^(-dt/tau),  s = (u1 - u0)/dt
  -- Frame-rate independent: a steady mover renders with a constant s*tau
  -- trail at any fps (a per-frame EMA's trail varies with frame rate).
  local u0 = slot.lerp_prev
  local y0 = slot.aux_v
  local kdt = dt / tau
  local trail = (raw - u0) / kdt
  local y = raw - trail + (y0 - u0 + trail) * math.exp(-kdt)
  slot.aux_v = y
  slot.lerp_prev = raw
  slot.aux_t = now
  return y
end

--- The undamped interpolant — _compute_lerp minus the output spring.
function Predict:_compute_lerp_raw(slot)
  local count = slot.ring_count
  if count == 0 then return slot.v1 end
  local head = slot.ring_head
  local start = (head - count + RING_CAP) % RING_CAP
  local newest = (start + count - 1) % RING_CAP
  if count == 1 then return slot.ring_v[newest + 1] end

  local clock = self._clock
  local target
  if clock ~= nil and clock:last_server_time() > 0 then
    target = clock:server_now() - slot.opts.delay - clock:smoothed_rtt() / 2
  else
    target = self._render_time - slot.opts.delay
  end

  -- hold at the ends — NEVER extrapolate
  if target <= slot.ring_t[start + 1] then return slot.ring_v[start + 1] end
  if target >= slot.ring_t[newest + 1] then return slot.ring_v[newest + 1] end

  -- walk back to the bracketing pair
  local k = count - 2
  local phys = (start + k) % RING_CAP
  while k > 0 do
    if slot.ring_t[phys + 1] <= target then break end
    k = k - 1
    phys = (phys == 0) and (RING_CAP - 1) or (phys - 1)
  end
  local b = (phys + 1 >= RING_CAP) and 0 or (phys + 1)
  local t_a = slot.ring_t[phys + 1]
  local t_b = slot.ring_t[b + 1]
  local span = t_b - t_a
  if span <= 0 then return slot.ring_v[b + 1] end
  local u = (target - t_a) / span
  return slot.ring_v[phys + 1] + (slot.ring_v[b + 1] - slot.ring_v[phys + 1]) * u
end

function Predict:_compute_extrapolate(slot)
  local count = slot.ring_count
  if count == 0 then return slot.v1 end
  local head = slot.ring_head
  local start = (head - count + RING_CAP) % RING_CAP
  local newest = (start + count - 1) % RING_CAP
  local newest_t = slot.ring_t[newest + 1]
  local newest_v = slot.ring_v[newest + 1]
  local now = self._render_time

  local raw
  if count == 1 then
    raw = newest_v
  else
    -- 2-step lookback flattens single-sample noise
    local steps = (count >= 3) and 2 or 1
    local lb = (start + count - 1 - steps + RING_CAP) % RING_CAP
    local dt = newest_t - slot.ring_t[lb + 1]
    if dt <= 0 then
      raw = newest_v
    else
      local slope = (newest_v - slot.ring_v[lb + 1]) / dt
      local ahead = now - newest_t
      if ahead < 0 then ahead = 0 end
      if ahead > slot.opts.max_extrapolate then ahead = slot.opts.max_extrapolate end
      raw = newest_v + slope * ahead
    end
  end

  local last_t = slot.aux_t
  slot.aux_t = now
  local tau = slot.opts.smooth_ms or DEFAULT_SMOOTH_MS
  if tau <= 0 then
    slot.aux_v = raw
    return raw
  end
  local dt_frame = now - last_t
  if dt_frame > 0 then
    local k = 1 - math.exp(-dt_frame / tau)
    slot.aux_v = slot.aux_v + (raw - slot.aux_v) * k
  end
  return slot.aux_v
end

function Predict:_compute_reckon(slot)
  local sim = self._sims_by_ref[slot.instance.__refid]
  if sim ~= nil then
    for k, f in ipairs(sim.fields) do
      if f == slot.field then
        self:_apply_simulation(sim)
        return sim.smoothed[k]
      end
    end
  end
  return slot.v1
end

--- Forward-sim the scratch instance from the latest snapshot by forward_ms.
function Predict:_advance(sim, forward_ms, output, end_elapsed)
  for _, f in ipairs(sim.copy_fields) do
    sim.scratch[f] = sim.instance[f]
  end
  local remaining = forward_ms
  local elapsed = end_elapsed - forward_ms
  while remaining > 0 do
    local step_ms = math.min(remaining, sim.substep)
    elapsed = elapsed + step_ms
    sim.step(sim.scratch, step_ms / 1000, elapsed)
    remaining = remaining - step_ms
  end
  for k, f in ipairs(sim.fields) do
    output[k] = to_number(sim.scratch[f])
  end
end

--- Once per frame per instance: advance + offset-decay smoothing.
function Predict:_apply_simulation(sim)
  local now = self._render_time
  if sim.last_apply_time == now then return end

  local n = #sim.fields
  local clock = self._clock
  local base_t = (clock ~= nil) and clock:last_server_time() or nil
  local present = (clock ~= nil) and clock:server_now() or 0
  local forward
  if sim.forward_ms ~= nil then
    forward = sim.forward_ms()
  elseif base_t ~= nil and base_t > 0 then
    forward = math.max(0, present - base_t)
  else
    forward = 0
  end
  self:_advance(sim, forward, sim.out, present)

  local first = sim.last_apply_time == nil
  if first or sim.smooth_ms <= 0 then
    for k = 1, n do
      sim.offset[k] = 0
      sim.smoothed[k] = sim.out[k]
    end
  elseif base_t ~= nil then
    local dt_ms = math.max(0, math.min(now - sim.last_apply_time, 100))
    if base_t ~= sim.last_base_t and sim.last_base_t ~= nil then
      -- rebase: subtract EXPECTED motion so steady travel doesn't read as error
      for k = 1, n do
        local d = sim.smoothed[k] + sim.frame_vel[k] * dt_ms - sim.out[k]
        if sim.snap > 0 and math.abs(d) > sim.snap then
          sim.offset[k] = 0
        else
          sim.offset[k] = d
        end
      end
    elseif dt_ms > 0 then
      for k = 1, n do
        sim.frame_vel[k] = (sim.out[k] - sim.out_prev[k]) / dt_ms
      end
    end
    local decay = math.exp(-dt_ms / sim.smooth_ms)
    for k = 1, n do
      sim.offset[k] = sim.offset[k] * decay
      sim.smoothed[k] = sim.out[k] + sim.offset[k]
    end
  else
    -- no clock — plain EMA chase
    local dt_ms = math.max(0, math.min(now - sim.last_apply_time, 100))
    local k2 = 1 - math.exp(-dt_ms / sim.smooth_ms)
    for k = 1, n do
      sim.smoothed[k] = sim.smoothed[k] + (sim.out[k] - sim.smoothed[k]) * k2
    end
  end
  for k = 1, n do sim.out_prev[k] = sim.out[k] end
  sim.last_base_t = base_t
  sim.last_apply_time = now
end

return Predict
