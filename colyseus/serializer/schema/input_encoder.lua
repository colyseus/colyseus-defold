--
-- Bound single-struct encoder for client→server input packets. Port of
-- @colyseus/schema `src/input/InputEncoder.ts` (flat primitive fields only).
--
-- Delta tracking differs from the JS reference by design: the reference uses
-- setter-populated ChangeTrees; this port diffs the instance against the
-- last-sent snapshot (seeded from construction defaults, so an unassigned
-- field is not dirty). Benign divergence: re-assigning an identical value
-- emits nothing — the server decodes to the same state either way.
--
--   * "reliable" mode: one delta per encode() — only changed fields, empty
--     when nothing changed. Bytes decode through the standard schema decoder.
--   * "unreliable" mode: ring of the last `history_size` deltas, one packet:
--     [baseSeq][len][slot]… oldest→newest; slot i has seq baseSeq+i. A
--     no-change tick still pushes an empty carry-forward slot.
--
local bit = require 'colyseus.serializer.bit'
local encode = require 'colyseus.serializer.schema.encoding.encode'
local quantize = require 'colyseus.serializer.schema.quantize'

local InputEncoder = {}
InputEncoder.__index = InputEncoder

---@param instance table schema instance (flat primitives only)
---@param mode string|nil "reliable" (default) | "unreliable"
---@param history_size number|nil unreliable redundancy ring size (default 3)
function InputEncoder.new(instance, mode, history_size)
  local self = setmetatable({}, InputEncoder)
  self.instance = instance
  self.mode = mode or "reliable"
  self.history_size = (self.mode == "unreliable") and (history_size or 3) or 1

  -- framework input seq (unreliable): monotonic, kept across reset()
  self.seq = 0

  self._slots = {}
  self._slot_head = 0  -- 0-based next-write position
  self._slot_count = 0

  for i, field_name in ipairs(instance._fields_by_index) do
    local field_type = instance._schema[field_name]
    if type(field_type) == "table" and field_type.quantized == nil then
      error("InputEncoder: non-primitive field '" .. field_name .. "' is not supported.")
    end
  end

  -- diff against construction defaults from the start — an unassigned field
  -- is not dirty (the JS ChangeTree behaves the same way)
  self._baseline = {}
  for i, field_name in ipairs(instance._fields_by_index) do
    self._baseline[i] = instance[field_name]
  end

  return self
end

--- Encode the bound instance's delta (see module doc for the shape per mode).
--- Returns a byte array (1-based Lua table).
function InputEncoder:encode()
  local body = self:_produce_delta()
  if self.mode == "reliable" then
    return body
  end
  return self:_push_and_emit_ring(body)
end

--- Reset: drops the ring and the diff baseline, so the next encode() emits a
--- full snapshot of populated fields. `seq` is kept (monotonic across reset).
function InputEncoder:reset()
  self._baseline = nil
  self._slot_head = 0
  self._slot_count = 0
  self._slots = {}
end

--- Copy the bound instance's field values into `target` (same-type instance).
function InputEncoder:copy_into(target)
  for _, field_name in ipairs(self.instance._fields_by_index) do
    target[field_name] = self.instance[field_name]
  end
end

function InputEncoder:_produce_delta()
  local out = {}
  local snapshot = (self._baseline == nil) -- post-reset
  if snapshot then self._baseline = {} end

  for i, field_name in ipairs(self.instance._fields_by_index) do
    local current = self.instance[field_name]
    local changed
    if snapshot then
      changed = (current ~= nil)             -- snapshot: every populated field
    else
      changed = (current ~= self._baseline[i]) -- delta: diff vs last sent
    end

    if changed then
      table.insert(out, bit.bor(0x80, i - 1)) -- ADD|fieldIndex (wire is 0-based)
      self:_encode_value(out, self.instance._schema[field_name], current)
      self._baseline[i] = current
    end
  end
  return out
end

function InputEncoder:_encode_value(out, field_type, value)
  if type(field_type) == "table" and field_type.quantized ~= nil then
    local desc = field_type.quantized
    encode[desc.wire](out, quantize.quantize(desc, value))
  else
    local fn = encode[field_type]
    if fn == nil then
      error("InputEncoder: unsupported field type '" .. tostring(field_type) .. "'")
    end
    fn(out, value)
  end
end

function InputEncoder:_push_and_emit_ring(body)
  -- push EVERY tick (even empty) so ring seqs stay consecutive: the packet
  -- carries one base seq; the decoder derives slot seqs by position
  self.seq = self.seq + 1
  self._slots[self._slot_head + 1] = body
  self._slot_head = (self._slot_head + 1) % self.history_size
  if self._slot_count < self.history_size then
    self._slot_count = self._slot_count + 1
  end

  -- [baseSeq][len][slot]… oldest→newest
  local out = {}
  local base_seq = self.seq - self._slot_count + 1
  encode.number(out, base_seq)
  local oldest = (self._slot_head - self._slot_count + self.history_size) % self.history_size
  for i = 0, self._slot_count - 1 do
    local slot = self._slots[((oldest + i) % self.history_size) + 1]
    encode.number(out, #slot)
    for j = 1, #slot do table.insert(out, slot[j]) end
  end
  return out
end

return InputEncoder
