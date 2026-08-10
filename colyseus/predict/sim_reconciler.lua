--
-- SimReconciler — the COMPOSITE face of the same rollback engine that drives
-- Reconciler (port of predict/simReconciler.ts).
--
-- Where the flat reconciler predicts ONE entity's scalar fields, this predicts a
-- WORLD of parts and reads back a pose keyed "<key>.<field>".
--
-- The world is just a table, which makes this the closest of the ports to the
-- JS reference: entries holding a DECODED schema instance are auto-bound —
-- replaced IN PLACE by mirrors the controller seeds, re-adopts on every ack, and
-- poses — and every other entry is opaque and untouched.
--
--   local sim = predict:sim({
--     input = input,
--     world = { paddle = state.players[sid], puck = state.puck },
--     step = function(ctx, w, cmd)
--       w.paddle.x = w.paddle.x + w.paddle.vx * ctx.dt
--       w.puck.x = w.puck.x + w.puck.vx * ctx.dt
--     end,
--   })
--   sim.world.paddle   -- the mirror; the table you passed in was mutated
--   sim:value("paddle.x")
--
-- The engine — catch-up, reconcile, error rebase, snap, drift, memos, epoch
-- follow — is inherited verbatim; only the state hooks differ. Notably
-- _truth_matches_at stays false: a composite sim has no wire-precision
-- short-circuit and always adopts, so the reference expects a little float noise
-- in the correction rather than an exact zero.
--
-- Bound entries register into predict:value(), so the render layer reads them
-- the same way it reads any other entity — predict:value(state.puck, "x") — and
-- the "key.field" pose key stays an internal detail.
--
-- NOT ported (see PORTING.md): the custom `pose`/`interpolate` overlays that
-- give OPAQUE parts render smoothing. Those have no decoded instance to key on,
-- so :value(pose_key) remains the only way to read them.
--
local RollbackController = require 'colyseus.predict.rollback'

local SimReconciler = setmetatable({}, { __index = RollbackController })
SimReconciler.__index = SimReconciler

local NON_SCALAR = { ref = true, array = true, map = true, string = true }

local function is_scalar_type(t)
  return type(t) == "string" and not NON_SCALAR[t]
end

--- A decoded schema instance is what auto-binding keys on; anything else in the
--- world table is the app's own business.
local function is_decoded_instance(v)
  return type(v) == "table" and rawget(v, "__refid") ~= nil
    and type(v._schema) == "table"
end

---@param opts table {input, world, step = fun(ctx, world, command), adopt?, ...rollback opts}
function SimReconciler.new(opts)
  local self = setmetatable({}, SimReconciler)
  RollbackController.init(self, opts)

  self._step = opts.step
  assert(self._step ~= nil, "SimReconciler: step required")
  self.world = opts.world
  assert(type(self.world) == "table", "SimReconciler: world table required")
  self._adopt = opts.adopt

  self._bound = {}         -- { source, mirror, fields }
  self._pose_keys = {}     -- "<key>.<field>", sorted for a stable order
  self._pose_of = {}       -- pose key -> { bound, field }

  -- pairs() order is unspecified, so collect the keys and sort: nothing in the
  -- algorithm depends on order, but an unstable pose list makes diagnostics and
  -- any future serialization needlessly annoying.
  local keys = {}
  for k in pairs(self.world) do table.insert(keys, tostring(k)) end
  table.sort(keys)

  for _, key in ipairs(keys) do
    local value = self.world[key]
    if is_decoded_instance(value) then
      self:_bind(key, value)
    end
  end

  -- Without a bound entry there is nothing to restore from, so an adopt callback
  -- is the only possible restore point.
  assert(#self._bound > 0 or self._adopt ~= nil,
    "SimReconciler: no world entry holds a decoded schema instance, so `adopt` is " ..
    "required — otherwise a replay has no state to roll back to.")

  table.sort(self._pose_keys)
  return self
end

---@private
function SimReconciler:_bind(key, source)
  -- Same as the flat face: the predicted state is a same-class schema mirror, so
  -- a step writes `w.paddle.vy = ...` against a real typed instance.
  local mirror = getmetatable(source):new()
  local bound = { key = key, source = source, mirror = mirror, fields = {} }

  for _, field in ipairs(source._fields_by_index) do
    if is_scalar_type(source._schema[field]) then
      local value = source[field]
      mirror[field] = value
      table.insert(bound.fields, field)

      local pose_key = key .. "." .. field
      self._pose_of[pose_key] = { bound = bound, field = field }
      if type(value) == "number" then
        table.insert(self._pose_keys, pose_key)
        self._prev[pose_key] = value
        self._error[pose_key] = 0
      end
    end
  end

  assert(#bound.fields > 0,
    "SimReconciler: bound world entry '" .. key .. "' has no scalar schema fields.")

  -- In place, exactly like the JS reference: the table the caller passed now
  -- points at the mirror, so `world.paddle` is what the step mutates.
  self.world[key] = mirror
  table.insert(self._bound, bound)
end

---@private
function SimReconciler:_read_pose(pose_key)
  local slot = self._pose_of[pose_key]
  if slot == nil then return nil end
  local v = slot.bound.mirror[slot.field]
  if type(v) ~= "number" then return nil end
  return v
end

--- Rendered pose for "<key>.<field>": the predicted value interpolated between
--- the two latest steps plus the decaying correction offset. nil for an unknown
--- key.
function SimReconciler:value(pose_key)
  local current = self:_read_pose(pose_key)
  if current == nil then return nil end
  local smoothed = current + (self._error[pose_key] or 0)
  local p = self._prev[pose_key]
  if p == nil then p = smoothed end
  return p + (smoothed - p) * self:_render_alpha()
end

--- Every pose key this world exposes — useful when one reads nil.
function SimReconciler:pose_keys()
  return self._pose_keys
end

--- What `predict:value(instance, field)` needs to reach this controller's poses:
--- the ORIGINAL decoded instance per bound entry (not the mirror), its numeric
--- fields, and the "<key>.<field>" each maps to. Keeps the composite key an
--- internal detail — the render layer reads `predict:value(state.puck, "x")`.
function SimReconciler:bound_registrations()
  local out = {}
  for _, b in ipairs(self._bound) do
    local fields, keys = {}, {}
    for _, f in ipairs(b.fields) do
      local key = b.key .. "." .. f
      if self._pose_of[key] ~= nil and type(b.mirror[f]) == "number" then
        table.insert(fields, f)
        table.insert(keys, key)
      end
    end
    if #fields > 0 then
      table.insert(out, { source = b.source, fields = fields, pose_keys = keys })
    end
  end
  return out
end

-- --- RollbackController hooks ---------------------------------------------

function SimReconciler:_smoothed_fields()
  return self._pose_keys
end

function SimReconciler:_read_current(pose_key)
  return self:_read_pose(pose_key)
end

function SimReconciler:_apply_step(command)
  self._step(self._ctx, self.world, command)
end

function SimReconciler:_snapshot_prev()
  for _, key in ipairs(self._pose_keys) do
    self._prev[key] = self:_read_pose(key) + (self._error[key] or 0)
  end
end

--- Pull every mirror back from its source, then let the app restore the opaque
--- entries. Bound entries are unconditional: unlike the flat face there is no
--- per-field wire-precision comparison to skip on.
function SimReconciler:_adopt_truth()
  for _, b in ipairs(self._bound) do
    for _, f in ipairs(b.fields) do
      b.mirror[f] = b.source[f]
    end
  end
  if self._adopt ~= nil then self._adopt(self.world) end
end

function SimReconciler:_reseed_state()
  self:_adopt_truth()
  for _, key in ipairs(self._pose_keys) do
    self._prev[key] = self:_read_pose(key)
    self._error[key] = 0
  end
end

return SimReconciler
