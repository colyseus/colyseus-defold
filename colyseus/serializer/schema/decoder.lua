local bit = require 'colyseus.serializer.bit'
local quantize = require 'colyseus.serializer.schema.quantize'
local map_schema = require 'colyseus.serializer.schema.types.map_schema'
local array_schema = require 'colyseus.serializer.schema.types.array_schema'
local decode = require 'colyseus.serializer.schema.encoding.decode'
local constants = require 'colyseus.serializer.schema.constants'
local reference_tracker = require 'colyseus.serializer.schema.reference_tracker'
local type_context = require 'colyseus.serializer.schema.type_context'
local types = require 'colyseus.serializer.schema.types'
local schema = require 'colyseus.serializer.schema.schema'

local SPEC = constants.SPEC;
local OPERATION = constants.OPERATION;

local function instance_of(subject, super)
  super = tostring(super)
  local mt = getmetatable(subject)

  while true do
    if mt == nil then return false end
    if tostring(mt) == super then return true end

    mt = getmetatable(mt)
  end
end

---@param decoder Decoder
---@param bytes number[]
---@param it table
---@param ref Schema
---@param all_changes table
schema.Schema.__decode = function(decoder, bytes, it, ref, all_changes)
  local byte = bytes[it.offset]
  it.offset = it.offset + 1

  --
  -- compressed operation:
  -- index + operation -> (byte >> 6) << 6
  --
  local operation = (bit.lshift(bit.arshift(byte, 6), 6))
  local field_index = (byte % ((operation == 0) and 255 or operation)) + 1

  local field_name = ref._fields_by_index[field_index]
  if field_name == nil then return constants.SCHEMA_MISMATCH end

  local field_type = ref._schema[field_name]
  local value, previous_value = decoder:decode_value(decoder, operation, ref, field_index, field_type, bytes, it, all_changes)

  if value ~= nil then
    ref[field_name] = value
  end

  if value ~= previous_value then
    table.insert(all_changes, {
      __refid = ref.__refid,
      op = operation,
      field = field_name,
      value = value,
      previous_value = previous_value,
    })
  end
end

---@param decoder Decoder
---@param bytes number[]
---@param it table
---@param ref MapSchema
---@param all_changes table
map_schema.__decode = function(decoder, bytes, it, ref, all_changes)
  local operation = bytes[it.offset]
  it.offset = it.offset + 1

  if operation == OPERATION.CLEAR then
    ref:clear(all_changes, decoder.refs)
    return
  end

  local field_index = decode.number(bytes, it) + 1 -- lua indexes start in 1 instead of 0
  local field_type = ref._child_type

  local dynamic_index
  if bit.band(operation, OPERATION.ADD) == OPERATION.ADD then
    -- map schema dynamic index
    dynamic_index = (instance_of(ref, map_schema))
        and decode.string(bytes, it)
        or field_index

    ref:set_index(field_index, dynamic_index)
  else
    dynamic_index = ref:get_index(field_index)
  end

  local value, previous_value = decoder:decode_value(decoder, operation, ref, field_index, field_type, bytes, it, all_changes)

  -- resync bookkeeping — record even when the value is unchanged
  -- (the change list can't serve as the record: its pushes are gated)
  if decoder._resync_visited ~= nil then
    decoder:_resync_touch(ref, operation, dynamic_index, previous_value, value, all_changes)
  end

  if value ~= nil then
    ref:set_by_index(field_index, dynamic_index, value)
  end

  if value ~= previous_value then
    table.insert(all_changes, {
      __refid = ref.__refid,
      op = operation,
      field = nil,
      dynamic_index = dynamic_index,
      value = value,
      previous_value = previous_value,
    })
  end
end

---@param decoder Decoder
---@param bytes number[]
---@param it table
---@param ref ArraySchema
---@param all_changes table
array_schema.__decode = function(decoder, bytes, it, ref, all_changes)
  local operation = bytes[it.offset]
  it.offset = it.offset + 1

  local index

  if operation == OPERATION.CLEAR then
    ref:clear(all_changes, decoder.refs)
    return

  elseif operation == OPERATION.REVERSE then
    ref:reverse()
    return

  elseif operation == OPERATION.DELETE_BY_REFID then
    local ref_id = decode.number(bytes, it) + 1
    local item = decoder.refs:get(ref_id)

    -- stale DELETE: ref_id unknown to this decoder (mid-tick joiner)
    if item == nil then return end

    -- ref-count decrement — must run even when the item is absent from
    -- THIS array (view churn); this branch never reaches decode_value()
    decoder.refs:remove(ref_id)

    local index = ref:index_of(item)
    if index == -1 then return end

    ref:delete_by_index(index)
    table.insert(all_changes, {
      __refid = ref.__refid,
      op = OPERATION.DELETE,
      field = nil,
      dynamic_index = index,
      value = nil,
      previous_value = item,
    })
    return

  elseif operation == OPERATION.ADD_BY_REFID then
    local ref_id = decode.number(bytes, it) + 1
    local item = decoder.refs:get(ref_id)

    if item ~= nil then
      index = ref:index_of(item)
    end

    -- fallback to use last index
    if index == -1 or index == nil then
      index = ref:length() + 1
    end

  else
    index = decode.number(bytes, it) + 1
  end

  local field_type = ref._child_type

  local value, previous_value = decoder:decode_value(decoder, operation, ref, index, field_type, bytes, it, all_changes)

  -- resync bookkeeping — identity is the resolved 1-based client-side index
  -- (ADD_BY_REFID resolves above, so visited indexes may be sparse)
  if decoder._resync_visited ~= nil then
    decoder:_resync_touch(ref, operation, index, previous_value, value, all_changes)
  end

  if value ~= nil and value ~= previous_value then
    -- resync snapshot ADDs are positional overwrites, not inserts
    local write_op = (decoder._resync_visited ~= nil and operation == OPERATION.ADD)
        and OPERATION.REPLACE
        or operation
    ref:set_by_index(index, value, write_op)
  end

  if value ~= previous_value then
    table.insert(all_changes, {
      __refid = ref.__refid,
      op = operation,
      field = nil,
      dynamic_index = index,
      value = value,
      previous_value = previous_value,
    })
  end
end

local function decode_primitive_type(field_type, bytes, it)
    local func = decode[field_type]
    if func then return func(bytes, it) else return nil end
end

---@class Decoder
---@field state Schema
---@field refs reference_tracker
---@field context type_context
---@field _trigger_changes function
local Decoder = {}
Decoder.__index = Decoder

---@param state Schema
---@param context type_context|nil
---@return Decoder
function Decoder:new(state, context)
  local instance = {
    state = state,
    context = context or type_context:new(),
		refs = reference_tracker:new(),
    _trigger_changes = function() end,

    -- non-nil only while decode_resync() is in progress — its non-nilness
    -- IS the resync-mode flag (see PORTING_RESYNC.md in @colyseus/schema).
    -- Keys are the SDK-internal 1-based __refids, never raw wire values.
    _resync_visited = nil,
    _resync_damaged = false,
	}
  setmetatable(instance, Decoder)

  -- set root state refid
  state.__refid = 1
  instance.refs:add(state.__refid, state, true)

	return instance
end

--
-- Full-snapshot reconciliation ("resync") decode.
--
-- Behaves exactly like decode(), plus: every collection entry the payload
-- does NOT mention is removed through the regular DELETE path — on_remove
-- callbacks fire with the real previous value and released refs are
-- garbage-collected. ONLY valid for full-snapshot payloads.
--
function Decoder:decode_resync(bytes, it)
  self._resync_visited = {}
  self._resync_damaged = false
  local ok, err = pcall(function() self:decode(bytes, it) end)
  self._resync_visited = nil
  if not ok then error(err) end
  return self
end

function Decoder:decode(bytes, it)
    if it == nil then it = { offset = 1 } end

    local ref_id = 1
    local ref = self.state

    local all_changes = {}

    local total_bytes = #bytes
    while it.offset <= total_bytes do repeat
        if bytes[it.offset] == SPEC.SWITCH_TO_STRUCTURE then
            it.offset = it.offset + 1

            ref_id = decode.number(bytes, it) + 1

            if ref['__on_decode_end'] ~= nil then ref:__on_decode_end() end

            local next_ref = self.refs:get(ref_id)

            --
            -- Trying to access a reference that haven't been decoded yet.
            --
            if next_ref == nil then
              print('@colyseus/schema: "ref_id" not found: ' .. ref_id)
              self:skip_current_structure(bytes, it, total_bytes)
            else
              ref = next_ref
            end

            break -- LUA "continue" workaround.
        end

        if ref.__decode(self, bytes, it, ref, all_changes) == constants.SCHEMA_MISMATCH then
          print("@colyseus/schema: definition mismatch (offset: " .. it.offset .. ", total: " .. total_bytes .. ")");
          self:skip_current_structure(bytes, it, total_bytes)

          -- LUA "continue" workaround.
          break
        end

    until true end

    if ref['__on_decode_end'] ~= nil then ref:__on_decode_end() end

    -- resync mode: prune everything the snapshot didn't visit. Runs before
    -- _trigger_changes (DELETE changes fire on_remove with the real
    -- previous_value) and before GC (refs:remove feeds deleted_refs).
    if self._resync_visited ~= nil then self:_resync_sweep(all_changes) end

    self:_trigger_changes(all_changes, self.refs)

    self.refs:garbage_collection()

    return self
end

--
-- keep skipping next bytes until reaches a known structure
-- by local decoder.
--
function Decoder:skip_current_structure(bytes, it, total_bytes)
  -- a skipped range can swallow other structures' ops — resync visited
  -- data is no longer trustworthy
  if self._resync_visited ~= nil then self._resync_damaged = true end

  local next_iterator = { offset = it.offset }
  while it.offset <= total_bytes do
      if bytes[it.offset] == SPEC.SWITCH_TO_STRUCTURE then
          next_iterator.offset = it.offset + 1;

          -- (wire refids are 0-based; the tracker is 1-based)
          if self.refs:has(decode.number(bytes, next_iterator) + 1) then
              break
          end
      end

      it.offset = it.offset + 1
  end
end

-- ─── resync bookkeeping (guarded by `_resync_visited ~= nil` at call sites) ───

--
-- Record that `identity` (map string key / 1-based array index) appeared in
-- the payload — even when its value is unchanged. Also releases a replaced
-- occupant: full-sync emits plain ADD (never DELETE_AND_ADD), so an entry
-- whose instance changed while off the wire would otherwise leak its
-- previous ref. Resync-only — a live patch's plain ADD can be a positional
-- rewrite where the occupant moved and is still alive.
--
function Decoder:_resync_touch(ref, operation, identity, previous_value, value, all_changes)
  local visited = self._resync_visited[ref.__refid]
  if visited == nil then
    visited = {}
    self._resync_visited[ref.__refid] = visited
  end
  visited[identity] = true

  if previous_value ~= nil and operation == OPERATION.ADD and previous_value ~= value
     and type(previous_value) == "table" and previous_value.__refid ~= nil then
    self.refs:remove(previous_value.__refid)
    table.insert(all_changes, {
      __refid = ref.__refid,
      op = OPERATION.DELETE,
      field = nil,
      dynamic_index = identity,
      value = nil,
      previous_value = previous_value,
    })
  end
end

function Decoder:_resync_sweep(all_changes)
  if self._resync_damaged then
    print("@colyseus/schema: resync sweep skipped — parts of the payload could not be decoded. Stale entries may persist until the next resync.")
    return
  end
  self:_sweep_schema(self.state, {}, all_changes)
end

function Decoder:_sweep_schema(ref, seen, all_changes)
  if ref.__refid == nil or seen[ref.__refid] then return end
  seen[ref.__refid] = true

  for _, field_name in ipairs(ref._fields_by_index) do
    local field_type = ref._schema[field_name]
    if type(field_type) ~= "string" then
      local value = ref[field_name]
      if value ~= nil then
        if field_type['_schema'] ~= nil then
          self:_sweep_schema(value, seen, all_changes)
        else
          self:_sweep_collection(value, seen, all_changes)
        end
      end
    end
  end
end

function Decoder:_sweep_collection(coll, seen, all_changes)
  if coll.__refid == nil or seen[coll.__refid] then return end
  seen[coll.__refid] = true

  -- nil = the collection never appeared in the payload at all — it is not
  -- part of full-sync (@transient, view-invisible) and must be left alone.
  -- An empty table means "present with zero entries" → prune everything.
  local visited = self._resync_visited[coll.__refid]
  if visited == nil then return end

  local prune = function(value, identity)
    table.insert(all_changes, {
      __refid = coll.__refid,
      op = OPERATION.DELETE,
      field = nil,
      dynamic_index = identity,
      value = nil,
      previous_value = value,
    })
    if type(value) == "table" and value.__refid ~= nil then
      self.refs:remove(value.__refid)
    end
  end
  -- recurse so nested collections of retained entries sweep too; swept
  -- subtrees are left to the GC's transitive walk instead (sweeping them
  -- directly would double-decrement shared children)
  local keep = function(value)
    if type(value) == "table" and value._schema ~= nil then
      self:_sweep_schema(value, seen, all_changes)
    end
  end

  coll:__resync_prune(visited, prune, keep)
end

---@return any, any
function Decoder:decode_value(decoder, operation, ref, field_index, field_type, bytes, it, all_changes)
  local value = nil
  local previous_value = ref:get_by_index(field_index)

  --
  -- DELETE operations
  --
  if bit.band(operation, OPERATION.DELETE) == OPERATION.DELETE then
    -- Flag `ref_id` for garbage collection.
    if type(previous_value) == "table" and previous_value.__refid ~= nil then
      decoder.refs:remove(previous_value.__refid)
    end

    if operation ~= OPERATION.DELETE_AND_ADD then
      ref:delete_by_index(field_index)
    end

    value = nil
  end

  if operation == OPERATION.DELETE then
    --
    -- Don't do anything...
    --
  elseif type(field_type) == "table" and field_type.quantized ~= nil then
    --
    -- Quantized scalar: read the unsigned int of the descriptor's wire
    -- width, then dequantize — the instance only ever holds the wire-exact
    -- float64 (see quantize.lua).
    --
    local desc = field_type.quantized
    value = quantize.dequantize(desc, decode[desc.wire](bytes, it))

  elseif field_type['_schema'] ~= nil then
    --
    -- Direct schema reference ("ref")
    --
    local __refid = decode.number(bytes, it) + 1
    value = decoder.refs:get(__refid)

    if bit.band(operation, OPERATION.ADD) == OPERATION.ADD then
      local concrete_child_type = decoder:get_schema_type(bytes, it, field_type);
      if value == nil then
        value = concrete_child_type:new()
        value.__refid = __refid
      end

      decoder.refs:add(__refid, value, (
        value ~= previous_value or
        (operation == OPERATION.DELETE_AND_ADD and value == previous_value)
      ));
    end

  elseif type(field_type) == "string" then
    --
    -- primitive value!
    --
    value = decode_primitive_type(field_type, bytes, it)
  else
    local collection_type_id = next(field_type)

    local __refid = decode.number(bytes, it) + 1

    -- resync bookkeeping: mark the collection present in the payload —
    -- even with zero entries — so the sweep knows it participated
    if decoder._resync_visited ~= nil and decoder._resync_visited[__refid] == nil then
      decoder._resync_visited[__refid] = {}
    end

    value = decoder.refs:get(__refid)

    local value_ref
    if decoder.refs:has(__refid) then
      value_ref = previous_value or decoder.refs:get(__refid)
    else
      value_ref = types.get_type(collection_type_id):new()     -- get 'map_schema'/'array_schema' constructor
    end

    value = value_ref:clone()
    value.__refid = __refid
    value._child_type = field_type[collection_type_id]

    if previous_value ~= nil then
      if previous_value.__refid ~= nil and previous_value.__refid ~= __refid then

        --
        -- Trigger on_remove() if structure has been replaced.
        --
        previous_value:each(function(val, key)
          if type(val) == "table" and val.__refid ~= nil then
            decoder.refs:remove(val.__refid)
          end

          table.insert(all_changes, {
            __refid = previous_value.__refid,
            op = OPERATION.DELETE,
            field = key,
            value = nil,
            previous_value = val,
          })
        end)
      end
    end

    decoder.refs:add(__refid, value, (
      value_ref ~= previous_value or
      (operation == OPERATION.DELETE_AND_ADD and value_ref == previous_value)
    ))
  end

  return value, previous_value
end

function Decoder:get_schema_type(bytes, it, default_type)
  local schema_type = default_type;

  if (bytes[it.offset] == SPEC.TYPE_ID) then
    it.offset = it.offset + 1

    local type_id = decode.number(bytes, it)
    schema_type = self.context:get(type_id)
  end

  return schema_type;
end

function Decoder:create_instance_type(bytes, it, typeref)
    if bytes[it.offset] == SPEC.TYPE_ID then
        it.offset = it.offset + 1
        local another_type = self.context:get(decode.uint8(bytes, it))
        return another_type:new()
    else
        return typeref:new()
    end
end

return Decoder