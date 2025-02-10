local bit = require 'colyseus.serializer.bit'
local map_schema = require 'colyseus.serializer.schema.types.map_schema'
local decode = require 'colyseus.serializer.schema.encoding.decode'
local constants = require 'colyseus.serializer.schema.constants'
local reference_tracker = require 'colyseus.serializer.schema.reference_tracker'
local type_context = require 'colyseus.serializer.schema.type_context'
local types = require 'colyseus.serializer.schema.types'

local SPEC = constants.SPEC;
local OPERATION = constants.OPERATION;

local function decode_primitive_type(field_type, bytes, it)
    local func = decode[field_type]
    if func then return func(bytes, it) else return nil end
end

local function instance_of(subject, super)
  super = tostring(super)
  local mt = getmetatable(subject)

  while true do
    if mt == nil then return false end
    if tostring(mt) == super then return true end

    mt = getmetatable(mt)
  end
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
    _trigger_changes = function() end
	}
  setmetatable(instance, Decoder)

  -- set root state refid
  state.__refid = 1
  instance.refs:set(state.__refid, state)

	return instance
end

function Decoder:decode(bytes, it)
    if it == nil then it = { offset = 1 } end

    local ref_id = 1
    local ref = self.state

    local all_changes = {}

    local total_bytes = #bytes
    while it.offset <= total_bytes do repeat
        local byte = bytes[it.offset]
        it.offset = it.offset + 1

        if byte == SPEC.SWITCH_TO_STRUCTURE then
            ref_id = decode.number(bytes, it) + 1
            local next_ref = self.refs:get(ref_id)

            --
            -- Trying to access a reference that haven't been decoded yet.
            --
            if next_ref == nil then error('"ref_id" not found: ' .. ref_id) end

            ref = next_ref
            break -- LUA "continue" workaround.
        end

        local is_schema = (ref._schema ~= nil) and true or false

        --
        -- index operation
        -- compressed: index + operation -> (byte >> 6) << 6
        -- uncompressed: index -> byte
        --
        local operation = (is_schema)
            and (bit.lshift(bit.arshift(byte, 6), 6))
            or byte

        if operation == OPERATION.CLEAR then
            --
            -- TODO: refactor me!
            -- The `.clear()` method is calling `$root.removeRef(ref_id)` for
            -- each item inside this collection
            --
            ref:clear(all_changes, self.refs)

            -- LUA "continue" workaround.
            break
        end

        local field_index = ((is_schema)
          and (byte % ((operation == 0) and 255 or operation))
          or decode.number(bytes, it)) + 1 -- lua indexes start in 1 instead of 0

        local field_name
        if is_schema then
          field_name = ref._fields_by_index[field_index]
        else
          field_name = ""
        end

        local field_type = (is_schema)
          and ref._schema[field_name]
          or ref._child_type

        local value
        local previous_value
        local dynamic_index

        if not is_schema then
            previous_value = ref:get_by_index(field_index)

            if bit.band(operation, OPERATION.ADD) == OPERATION.ADD then
                dynamic_index = (instance_of(ref, map_schema))
                    and decode.string(bytes, it)
                    or field_index

                ref:set_index(field_index, dynamic_index)

            else
                dynamic_index = ref:get_index(field_index)
            end

        else
            previous_value = ref[field_name]
        end

        --
        -- DELETE operations
        --
        if bit.band(operation, OPERATION.DELETE) == OPERATION.DELETE then
          if operation ~= OPERATION.DELETE_AND_ADD then
              ref:delete_by_index(field_index)
          end

          -- Flag `ref_id` for garbage collection.
          if type(previous_value) == "table" and previous_value.__refid ~= nil then
              self.refs:remove(previous_value.__refid)
          end

          value = nil
        end

        if field_name == nil then
          print("@colyseus/schema: definition mismatch (offset: " .. it.offset .. ", total: " .. total_bytes .. ")");

          --
          -- keep skipping next bytes until reaches a known structure
          -- by local decoder.
          --
          local next_iterator = { offset = it.offset }
          while it.offset <= total_bytes do
              if bytes[it.offset] == SPEC.SWITCH_TO_STRUCTURE then
                  next_iterator.offset = it.offset + 1;

                  if self.refs:has(decode.number(bytes, next_iterator)) then
                      break
                  end
              end

              it.offset = it.offset + 1
          end

          -- LUA "continue" workaround.
          break

        elseif operation == OPERATION.DELETE then
          --
          -- ??
          -- Don't do anything...
          --

        elseif field_type['_schema'] ~= nil then
          --
          -- Direct schema reference ("ref")
          --
          local __refid = decode.number(bytes, it) + 1
          value = self.refs:get(__refid)

          if operation ~= OPERATION.REPLACE then
              local concrete_child_type = self:get_schema_type(bytes, it, field_type);

              if value == nil then
                  value = concrete_child_type:new()
                  value.__refid = __refid

                  if previous_value ~= nil then
                      -- copy previous callbacks
                      value.__callbacks = previous_value.__callbacks

                      if (
                          previous_value.__refid and
                          previous_value.__refid ~= __refid
                      ) then
                          self.refs:remove(previous_value.__refid);
                      end
                  end
              end

              self.refs:set(__refid, value, (value ~= previous_value));
          end

        elseif type(field_type) == "string" then
          --
          -- primitive value!
          --
          value = decode_primitive_type(field_type, bytes, it)

        else
          local collection_type_id = next(field_type)

          local __refid = decode.number(bytes, it) + 1
          value = self.refs:get(__refid)

          local value_ref = (self.refs:has(__refid))
            and previous_value
            or types.get_type(collection_type_id):new() -- get 'map_schema'/'array_schema' constructor

          value = value_ref:clone()
          value.__refid = __refid
          value._child_type = field_type[collection_type_id]

          if previous_value ~= nil then
              -- copy callbacks
              value.__callbacks = previous_value.__callbacks

              if (
                previous_value.__refid ~= nil and
                previous_value.__refid ~= __refid
              ) then
                self.refs:remove(previous_value.__refid)

                --
                -- Trigger on_remove() if structure has been replaced.
                --
                previous_value:each(function(val, key)
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

          self.refs:set(__refid, value, (value_ref ~= previous_value))
        end

        local has_change = (previous_value ~= value)

        if value ~= nil then
          ref:set_by_index(field_index, dynamic_index, value)
        end

        if has_change then
          table.insert(all_changes, {
            __refid = ref_id,
            op = operation,
            field = field_name,
            dynamic_index = dynamic_index,
            value = value,
            previous_value = previous_value,
          })
        end

    until true end

    self:_trigger_changes(all_changes, self.refs)

    self.refs:garbage_collection()

    return self
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