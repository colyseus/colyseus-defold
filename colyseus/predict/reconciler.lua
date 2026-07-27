--
-- Server-reconciled rollback for a locally-controlled entity whose truth is
-- a flat scalar field list on ONE schema instance (port of the JS SDK's
-- predict/reconciler.ts). The predicted state is a same-class schema MIRROR
-- exposed as `self.state`; numeric fields get smooth error correction,
-- booleans copy verbatim.
--
local RollbackController = require 'colyseus.predict.rollback'
local encode = require 'colyseus.serializer.schema.encoding.encode'

local Reconciler = setmetatable({}, { __index = RollbackController })
Reconciler.__index = Reconciler

local MAX_SAFE_INTEGER = 9007199254740991

-- "string" fields can't error-correct; tables are refs/collections —
-- quantized descriptors are the one scalar table type (wire-exact float64)
local function is_scalar_type(field_type)
  if type(field_type) == "table" then return field_type.quantized ~= nil end
  return field_type ~= "string"
end

local function as_scalar(value)
  local t = type(value)
  if t == "number" then return value end
  if t == "boolean" then return value and 1 or 0 end
  return 0 / 0
end

--- Mirror of the codec's dynamic "number" wire rule — what value would the
--- wire deliver for this float64?
local function quantize_auto_number(v)
  if v ~= v then return 0 end
  if v == math.huge then return MAX_SAFE_INTEGER end
  if v == -math.huge then return -MAX_SAFE_INTEGER end
  local is_int32 = v == math.floor(v) and v >= -2147483648 and v <= 2147483647
  if not is_int32 and math.abs(v) <= 3.4028235e+38 then
    local f = encode.fround(v)
    if math.abs(math.abs(f) - math.abs(v)) < 1e-4 then return f end
  end
  return v
end

local function identity(v) return v end
local function fround_one(v) return (encode.fround(v)) end

local function wire_quantizer_of(instance, field)
  local declared = instance._schema[field]
  if declared == "float32" then return fround_one end
  if declared == "number" then return quantize_auto_number end
  return identity
end

---@param instance table decoded schema instance (the server truth)
---@param opts table {input, step = fun(ctx, state, command), fields?, ...rollback opts}
function Reconciler.new(instance, opts)
  local self = setmetatable({}, Reconciler)
  RollbackController.init(self, opts)

  self._instance = instance
  self._step = opts.step
  assert(self._step ~= nil, "Reconciler: step required")

  local declared = opts.fields
  if declared == nil then
    declared = {}
    for _, field in ipairs(instance._fields_by_index) do
      if is_scalar_type(instance._schema[field]) then
        table.insert(declared, field)
      end
    end
    assert(#declared > 0,
      "Reconciler: no fields given and none derivable from the schema.")
  end

  -- the predicted state is a same-class schema MIRROR: step mutates a real
  -- typed instance (state.vy = ...)
  local mirror = getmetatable(instance):new()
  self.state = mirror

  self._fields = {}
  self._numeric_fields = {}
  self._wire_round = {}
  local scalar_only = #declared > 0
  for i, f in ipairs(declared) do
    self._fields[i] = f
    local value = instance[f]
    mirror[f] = value
    if type(value) == "number" then
      table.insert(self._numeric_fields, f)
      self._prev[f] = value
      self._error[f] = 0
    elseif type(value) ~= "boolean" then
      scalar_only = false
    end
    self._wire_round[i] = wire_quantizer_of(instance, f)
  end

  -- wire-precision history ring: skip full adopt+replay when the acked truth
  -- matches what we predicted (to wire precision)
  self._history_on = scalar_only
  self._history_size = (self._input.replay_buffer_size ~= nil
    and self._input.replay_buffer_size > 0) and self._input.replay_buffer_size or 64
  self._history = {}
  self._history_seq = {}
  if self._history_on then
    for s = 1, self._history_size do self._history_seq[s] = -1 end
  end

  return self
end

--- Rendered value: the predicted state interpolated between the two latest
--- steps plus the decaying correction offset. Numeric fields only; others
--- return the current value.
function Reconciler:value(field)
  local current = self.state[field]
  if type(current) ~= "number" then return as_scalar(current) end
  local smoothed = current + (self._error[field] or 0)
  local p = self._prev[field]
  if p == nil then p = smoothed end
  return p + (smoothed - p) * self:_render_alpha()
end

--- What `predict:value(instance, field)` needs to reach this controller's poses.
--- Flat face: the pose key IS the field name, so the two lists match — but the
--- registration keeps them separate to share one overlay path with the
--- composite face, whose keys are "<worldKey>.<field>".
function Reconciler:bound_registrations()
  if #self._numeric_fields == 0 then return {} end
  return { {
    source = self._instance,
    fields = self._numeric_fields,
    pose_keys = self._numeric_fields,
  } }
end

-- --- RollbackController hooks ---------------------------------------------

function Reconciler:_smoothed_fields()
  return self._numeric_fields
end

function Reconciler:_read_current(field)
  return self.state[field]
end

function Reconciler:_apply_step(command)
  self._step(self._ctx, self.state, command)
  if self._history_on then
    local slot = self._ctx.tick % self._history_size
    local base = slot * #self._fields
    for i, f in ipairs(self._fields) do
      self._history[base + i] = as_scalar(self.state[f])
    end
    self._history_seq[slot + 1] = self._ctx.tick
  end
end

function Reconciler:_truth_matches_at(acked)
  if not self._history_on then return false end
  local slot = acked % self._history_size
  if self._history_seq[slot + 1] ~= acked then return false end
  local base = slot * #self._fields
  for i, f in ipairs(self._fields) do
    if self._wire_round[i](self._history[base + i]) ~= as_scalar(self._instance[f]) then
      return false
    end
  end
  return true
end

function Reconciler:_snapshot_prev()
  for _, f in ipairs(self._numeric_fields) do
    self._prev[f] = self.state[f] + (self._error[f] or 0)
  end
end

function Reconciler:_adopt_truth()
  for _, f in ipairs(self._fields) do
    self.state[f] = self._instance[f]
  end
end

function Reconciler:_reseed_state()
  for _, f in ipairs(self._fields) do
    self.state[f] = self._instance[f]
  end
  for _, f in ipairs(self._numeric_fields) do
    self._prev[f] = self.state[f]
    self._error[f] = 0
  end
  if self._history_on then
    for s = 1, self._history_size do self._history_seq[s] = -1 end
  end
end

return Reconciler
