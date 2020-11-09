--
-- @colyseus/schema decoder for LUA
--
-- This file is part of Colyseus: https://github.com/colyseus/colyseus
--
local bit = require 'colyseus.serialization.bit'
local ldexp = math.ldexp or mathx.ldexp

local encode = require 'colyseus.serialization.schema.encode'
local types = require 'colyseus.serialization.schema.types'
local map_schema = require 'colyseus.serialization.schema.types.map_schema'
local reference_tracker = require 'colyseus.serialization.schema.reference_tracker'

-- START SPEC + OPERATION --
local spec = {
    SWITCH_TO_STRUCTURE = 255,
    TYPE_ID = 213,
}

local OPERATION = {
  -- ADD new structure/primitive
  ADD = 128,

  -- REPLACE structure/primitive
  REPLACE = 0,

  -- DELETE field
  DELETE = 64,

  -- DELETE field, followed by an ADD
  DELETE_AND_ADD = 192,

  -- Collection Operations
  CLEAR = 10,
}
-- END SPEC + OPERATION --

function instance_of(subject, super)
  super = tostring(super)
  local mt = getmetatable(subject)

  while true do
    if mt == nil then return false end
    if tostring(mt) == super then return true end

    mt = getmetatable(mt)
  end
end

--
-- ordered_array
-- the ordered array is used to keep track of "all_changes", and ordered ref_id per change, as they are identified.
--
local ordered_array = {}
function ordered_array:new(obj)
    obj = {
        items = {},
        keys = {},
    }
    setmetatable(obj, ordered_array)
    return obj
end
function ordered_array:__index(key)
    return (type(key)=="number") and self.items[key] or rawget(self, key)
end
function ordered_array:__newindex(key, value)
    self.items[key] = value
    table.insert(self.keys, key)
end

-- START DECODE --
local function utf8_read(bytes, offset, length)
  local bytearr = {}
  local len = offset + length
  for i = offset, len - 1 do
      local byte = bytes[i]
      local utf8byte = byte < 0 and (0xff + byte + 1) or byte
      table.insert(bytearr, string.char(utf8byte))
  end
  return table.concat(bytearr)
end

local function uint8 (bytes, it)
    local int = bytes[it.offset]
    it.offset = it.offset + 1
    return int
end

local function int8 (bytes, it)
    return bit.arshift(bit.lshift(uint8(bytes, it), 24), 24)
end

local function boolean (bytes, it)
    return uint8(bytes, it) == 1
end

local function uint16 (bytes, it)
    local n1 = bytes[it.offset]
    it.offset = it.offset + 1

    local n2 = bytes[it.offset]
    it.offset = it.offset + 1

    return bit.bor(n1, bit.lshift(n2, 8))
end

local function int16 (bytes, it)
    return bit.arshift(bit.lshift(uint16(bytes, it), 16), 16)
end

local function int32 (bytes, it)
    local b4 = bytes[it.offset]
    local b3 = bytes[it.offset + 1]
    local b2 = bytes[it.offset + 2]
    local b1 = bytes[it.offset + 3]
    it.offset = it.offset + 4
    if b1 < 0x80 then
        return ((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4
    else
        return ((((b1 - 0xFF) * 0x100 + (b2 - 0xFF)) * 0x100 + (b3 - 0xFF)) * 0x100 + (b4 - 0xFF)) - 1
    end
end

local function uint32 (bytes, it)
    local b4 = bytes[it.offset]
    local b3 = bytes[it.offset + 1]
    local b2 = bytes[it.offset + 2]
    local b1 = bytes[it.offset + 3]
    it.offset = it.offset + 4
    return ((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4
end

local function int64 (bytes, it)
    local b8 = bytes[it.offset]
    local b7 = bytes[it.offset + 1]
    local b6 = bytes[it.offset + 2]
    local b5 = bytes[it.offset + 3]
    local b4 = bytes[it.offset + 4]
    local b3 = bytes[it.offset + 5]
    local b2 = bytes[it.offset + 6]
    local b1 = bytes[it.offset + 7]
    it.offset = it.offset + 8
    if b1 < 0x80 then
        return ((((((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4) * 0x100 + b5) * 0x100 + b6) * 0x100 + b7) * 0x100 + b8
    else
        return ((((((((b1 - 0xFF) * 0x100 + (b2 - 0xFF)) * 0x100 + (b3 - 0xFF)) * 0x100 + (b4 - 0xFF)) * 0x100 + (b5 - 0xFF)) * 0x100 + (b6 - 0xFF)) * 0x100 + (b7 - 0xFF)) * 0x100 + (b8 - 0xFF)) - 1
    end
end

local function uint64 (bytes, it)
    local b8 = bytes[it.offset]
    local b7 = bytes[it.offset + 1]
    local b6 = bytes[it.offset + 2]
    local b5 = bytes[it.offset + 3]
    local b4 = bytes[it.offset + 4]
    local b3 = bytes[it.offset + 5]
    local b2 = bytes[it.offset + 6]
    local b1 = bytes[it.offset + 7]
    it.offset = it.offset + 8
    return ((((((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4) * 0x100 + b5) * 0x100 + b6) * 0x100 + b7) * 0x100 + b8
end

local function float32(bytes, it)
    local b4 = bytes[it.offset]
    local b3 = bytes[it.offset + 1]
    local b2 = bytes[it.offset + 2]
    local b1 = bytes[it.offset + 3]
    local sign = b1 > 0x7F
    local expo = (b1 % 0x80) * 0x2 + math.floor(b2 / 0x80)
    local mant = ((b2 % 0x80) * 0x100 + b3) * 0x100 + b4
    if sign then
        sign = -1
    else
        sign = 1
    end
    local n
    if mant == 0 and expo == 0 then
        n = sign * 0.0
    elseif expo == 0xFF then
        if mant == 0 then
            n = sign * math.huge
        else
            n = 0.0/0.0
        end
    else
        n = sign * ldexp(1.0 + mant / 0x800000, expo - 0x7F)
    end
    it.offset = it.offset + 4
    return n
end

local function float64(bytes, it)
    local b8 = bytes[it.offset]
    local b7 = bytes[it.offset + 1]
    local b6 = bytes[it.offset + 2]
    local b5 = bytes[it.offset + 3]
    local b4 = bytes[it.offset + 4]
    local b3 = bytes[it.offset + 5]
    local b2 = bytes[it.offset + 6]
    local b1 = bytes[it.offset + 7]

    -- TODO: detect big/little endian?

    -- local b1 = bytes[it.offset]
    -- local b2 = bytes[it.offset + 1]
    -- local b3 = bytes[it.offset + 2]
    -- local b4 = bytes[it.offset + 3]
    -- local b5 = bytes[it.offset + 4]
    -- local b6 = bytes[it.offset + 5]
    -- local b7 = bytes[it.offset + 6]
    -- local b8 = bytes[it.offset + 7]

    local sign = b1 > 0x7F
    local expo = (b1 % 0x80) * 0x10 + math.floor(b2 / 0x10)
    local mant = ((((((b2 % 0x10) * 0x100 + b3) * 0x100 + b4) * 0x100 + b5) * 0x100 + b6) * 0x100 + b7) * 0x100 + b8
    if sign then
        sign = -1
    else
        sign = 1
    end
    local n
    if mant == 0 and expo == 0 then
        n = sign * 0.0
    elseif expo == 0x7FF then
        if mant == 0 then
            n = sign * math.huge
        else
            n = 0.0/0.0
        end
    else
        n = sign * ldexp(1.0 + mant / 4503599627370496.0, expo - 0x3FF)
    end
    it.offset = it.offset + 8
    return n
end

local function _string (bytes, it)
  local prefix = bytes[it.offset]
  it.offset = it.offset + 1

  local length

  if prefix < 0xc0 then
    length = bit.band(prefix, 0x1f) -- fixstr
  elseif prefix == 0xd9 then
    length = uint8(bytes, it)
  elseif prefix == 0xda then
    length = uint16(bytes, it)
  elseif prefix == 0xdb then
    length = uint32(bytes, it)
  else
    length = 0
  end

  local value = utf8_read(bytes, it.offset, length)
  it.offset = it.offset + length

  return value
end

local function string_check (bytes, it)
  local prefix = bytes[it.offset]
  return (
    -- fixstr
    (prefix < 192 and prefix > 160) or
    -- str 8
    prefix == 217 or
    -- str 16
    prefix == 218 or
    -- str 32
    prefix == 219
  )
end

local function number (bytes, it)
  local prefix = bytes[it.offset]
  it.offset = it.offset + 1

  if (prefix < 128) then
    -- positive fixint
    return prefix

  elseif (prefix == 202) then
    -- float 32
    return float32(bytes, it)

  elseif (prefix == 203) then
    -- float 64
    return float64(bytes, it)

  elseif (prefix == 204) then
    -- uint 8
    return uint8(bytes, it)

  elseif (prefix == 205) then
    -- uint 16
    return uint16(bytes, it)

  elseif (prefix == 206) then
    -- uint 32
    return uint32(bytes, it)

  elseif (prefix == 207) then
    return uint64(bytes, it)

  elseif (prefix == 208) then
    -- int 8
    return int8(bytes, it)

  elseif (prefix == 209) then
    -- int 16
    return int16(bytes, it)

  elseif (prefix == 210) then
    -- int 32
    return int32(bytes, it)

  elseif (prefix == 211) then
    -- int 64
    return int64(bytes, it)

  elseif (prefix > 223) then
    -- negative fixint
    return (255 - prefix + 1) * -1
  end
end

local function number_check (bytes, it)
  local prefix = bytes[it.offset]
  return (prefix < 128 or (prefix >= 202 and prefix <= 211))
end

local function array_check (bytes, it)
  return bytes[it.offset] < 160
end

local function switch_structure_check (bytes, it)
  return bytes[it.offset] == spec.SWITCH_TO_STRUCTURE
end

local decode = {
    boolean = boolean,
    int8 = int8,
    uint8 = uint8,
    int16 = int16,
    uint16 = uint16,
    int32 = int32,
    uint32 = uint32,
    int64 = int64,
    uint64 = uint64,
    float32 = float32,
    float64 = float64,
    number = number,
    string = _string,
    string_check = string_check,
    number_check = number_check,
    array_check = array_check,
    switch_structure_check = switch_structure_check,
    -- nil_check = nil_check,
    -- index_change_check = index_change_check,
}
-- END DECODE --


-- START UTIL FUNCTIONS --
local pprint = pprint or function(node)
    -- to make output beautiful
    local function tab(amt)
        local str = ""
        for i=1,amt do
            str = str .. "\t"
        end
        return str
    end

    local cache, stack, output = {},{},{}
    local depth = 1
    local output_str = "{\n"

    while true do
        local size = 0
        for k,v in pairs(node) do
            size = size + 1
        end

        local cur_index = 1
        for k,v in pairs(node) do
            if (cache[node] == nil) or (cur_index >= cache[node]) then

                if (string.find(output_str,"}",output_str:len())) then
                    output_str = output_str .. ",\n"
                elseif not (string.find(output_str,"\n",output_str:len())) then
                    output_str = output_str .. "\n"
                end

                -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
                table.insert(output,output_str)
                output_str = ""

                local key
                if (type(k) == "number" or type(k) == "boolean") then
                    key = "["..tostring(k).."]"
                else
                    key = "['"..tostring(k).."']"
                end

                if (type(v) == "number" or type(v) == "boolean") then
                    output_str = output_str .. tab(depth) .. key .. " = "..tostring(v)
                elseif (type(v) == "table") then
                    output_str = output_str .. tab(depth) .. key .. " = {\n"
                    table.insert(stack,node)
                    table.insert(stack,v)
                    cache[node] = cur_index+1
                    break
                else
                    output_str = output_str .. tab(depth) .. key .. " = '"..tostring(v).."'"
                end

                if (cur_index == size) then
                    output_str = output_str .. "\n" .. tab(depth-1) .. "}"
                else
                    output_str = output_str .. ","
                end
            else
                -- close the table
                if (cur_index == size) then
                    output_str = output_str .. "\n" .. tab(depth-1) .. "}"
                end
            end

            cur_index = cur_index + 1
        end

        if (size == 0) then
            output_str = output_str .. "\n" .. tab(depth-1) .. "}"
        end

        if (#stack > 0) then
            node = stack[#stack]
            stack[#stack] = nil
            depth = cache[node] == nil and depth + 1 or depth - 1
        else
            break
        end
    end

    -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
    table.insert(output,output_str)
    output_str = table.concat(output)

    print(output_str)
end

local function decode_primitive_type (field_type, bytes, it)
    local func = decode[field_type]
    if func then return func(bytes, it) else return nil end
end

function table.clone(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function table.keys(orig)
    local keyset = {}
    for k,v in pairs(orig) do
      keyset[#keyset + 1] = k
    end
    return keyset
end
-- END UTIL FUNCTIONS --

-- START CONTEXT CLASS --
local Context = {}
function Context:new(obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self
    obj.schemas = {}
    obj.types = {}
    return obj
end
function Context:get(typeid)
    return self.types[typeid]
end
function Context:add(schema, typeid)
    schema._typeid = typeid or #self.schemas
    self.types[schema._typeid] = schema
    table.insert(self.schemas, schema)
end
-- END CONTEXT CLASS --


-- START SCHEMA CLASS --
local Schema = {}

function Schema:new(obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self

    -- initialize child schema structures
    if self._schema ~= nil then
      for field, field_type in pairs(self._schema) do
          if type(field_type) ~= "string" then
              obj[field] = (field_type['new'] ~= nil)
                  and field_type:new()
                  or types.get_type(next(field_type)):new()
          end
      end
    end

    return obj
end

function Schema:trigger_all()
  local refs = self.__refs

  --
  -- first state not received from the server yet.
  -- nothing to trigger.
  --
  if refs == nil then return end

  local all_changes = ordered_array:new()
  self:_trigger_all_fill_changes(self, all_changes, refs)
  self:_trigger_changes(all_changes, refs)
end

function Schema:decode(bytes, it, refs)
    -- default iterator
    if it == nil then it = { offset = 1 } end

    -- default reference tracker
    if refs == nil then refs = reference_tracker:new() end

    self.__refs = refs

    local ref_id = 1
    local ref = self

    local changes = {}
    -- local all_changes = {}
    local all_changes = ordered_array:new()

    refs:set(ref_id, ref)
    all_changes[ref_id] = changes

    local total_bytes = #bytes
    while it.offset <= total_bytes do repeat
        local byte = bytes[it.offset]
        it.offset = it.offset + 1

        if byte == spec.SWITCH_TO_STRUCTURE then
            ref_id = decode.number(bytes, it) + 1

            local next_ref = refs:get(ref_id)

            --
            -- Trying to access a reference that haven't been decoded yet.
            --
            if next_ref == nil then error('"ref_id" not found: ' .. ref_id) end

            ref = next_ref

            -- create empty list of changes for this ref_id.
            changes = {}
            all_changes[ref_id] = changes

            -- LUA "continue" workaround.
            break
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
            ref:clear(refs)

            -- LUA "continue" workaround.
            break
        end

        local field_index = ((is_schema)
          and (byte % ((operation == 0) and 255 or operation))
          or decode.number(bytes, it)) + 1 -- lua indexes start in 1 instead of 0

        local field_name
        if is_schema
        then field_name = ref._fields_by_index[field_index]
        else field_name = ""
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
              refs:remove(previous_value.__refid)
          end

          value = nil
        end

        if field_name == nil then
          print("@colyseus/schema: definition mismatch");

          --
          -- keep skipping next bytes until reaches a known structure
          -- by local decoder.
          --
          local next_iterator = { offset = it.offset }
          while it.offset <= total_bytes do
              if decode.switch_structure_check(bytes, it) then
                  next_iterator.offset = it.offset + 1;

                  if refs:has(decode.number(bytes, next_iterator)) then
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
          ref_id = decode.number(bytes, it) + 1
          value = refs:get(ref_id)

          if operation ~= OPERATION.REPLACE then
              local concrete_child_type = self:get_schema_type(bytes, it, field_type);

              if value == nil then
                  value = concrete_child_type:new()
                  value.__refid = ref_id

                  if previous_value ~= nil then
                      value['on_change'] = previous_value['on_change'];
                      value['on_remove'] = previous_value['on_remove'];
                      -- value.$listeners = previous_value.$listeners;

                      if (
                          previous_value.__refid and
                          previous_value.__refid ~= ref_id
                      ) then
                          refs:remove(previous_value.__refid);
                      end
                  end
              end

              refs:set(ref_id, value, (value ~= previous_value));
          end

        elseif type(field_type) == "string" then
          --
          -- primitive value!
          --
          value = decode_primitive_type(field_type, bytes, it)

        else
          local collection_type_id = next(field_type)

          ref_id = decode.number(bytes, it) + 1
          value = refs:get(ref_id)

          local value_ref = (refs:has(ref_id))
            and previous_value
            or types.get_type(collection_type_id):new() -- get 'map_schema'/'array_schema' constructor

          value = value_ref:clone()
          value.__refid = ref_id
          value._child_type = field_type[collection_type_id]

          if previous_value ~= nil then
              value['on_add'] = previous_value['on_add']
              value['on_remove'] = previous_value['on_remove']
              value['on_change'] = previous_value['on_change']

              if (
                previous_value.__refid ~= nil and
                previous_value.__refid ~= ref_id
              ) then
                refs:remove(previous_value.__refid)

                --
                -- Trigger onRemove if structure has been replaced.
                --
                local deletes = {}
                previous_value:each(function(val, key)
                  table.insert(deletes, {
                    op = OPERATION.DELETE,
                    field = key,
                    value = nil,
                    previous_value = val,
                  })
                end)

                all_changes[previous_value.__refid] = deletes

              end
          end

          refs:set(ref_id, value, (value_ref ~= previous_value))
        end

        local has_change = (previous_value ~= value)

        if value ~= nil then
          ref:set_by_index(field_index, dynamic_index, value)
        end

        if has_change then
          table.insert(changes, {
            op = operation,
            field = field_name,
            dynamic_index = dynamic_index,
            value = value,
            previous_value = previous_value,
          })
        end

    until true end

    self:_trigger_changes(all_changes, refs)

    refs:garbage_collection()

    return self
end

function Schema:set_by_index(field_index, dynamic_index, value)
  self[self._fields_by_index[field_index]] = value
end

function Schema:get_by_index(field_index)
  return self[self._fields_by_index[field_index]]
end

function Schema:delete_by_index(field_index)
  self[self._fields_by_index[field_index]] = nil
end

function Schema:_trigger_all_fill_changes(ref, all_changes, refs)
  -- skip if trying to enqueue a structure more than once.
  if all_changes[ref.__refid] ~= nil then return end

  local changes = {}
  all_changes[ref.__refid or 1] = changes

  if ref._schema ~= nil then
    for field, field_type in pairs(ref._schema) do
      if ref[field] ~= nil then
        table.insert(changes, {
          op = OPERATION.ADD,
          field = field,
          value = ref[field],
          previous_value = nil
        })

        if (
          type(ref[field]) == "table" and (
            ref[field]['_schema'] ~= nil or
            ref[field]._child_type ~= nil
          )
        ) then
          self:_trigger_all_fill_changes(ref[field], all_changes, refs)
        end
      end
    end

  else
    local has_schema_child = ref._child_type['_schema']

    ref:each(function(value, key)
      table.insert(changes, {
        op = OPERATION.ADD,
        field = nil,
        dynamic_index = key,
        value = value,
      })

      if has_schema_child then
        self:_trigger_all_fill_changes(value, all_changes, refs)
      end

    end)

  end
end

function Schema:_trigger_changes(all_changes, refs)
  for _, ref_id in ipairs(all_changes.keys) do
    local ref = refs:get(ref_id)
    local is_schema = ref['_schema'] ~= nil
    local changes = all_changes[ref_id]

    for _, change in ipairs(changes) do

      if not is_schema then
        if change.op == OPERATION.ADD and change.previous_value == nil then
          if ref['on_add'] ~= nil then
            ref['on_add'](change.value, change.dynamic_index)
          end

        elseif change.op == OPERATION.DELETE then
          --
          -- FIXME: `previous_value` should always be available.
          -- ADD + DELETE operations are still encoding DELETE operation.
          --
          if change.previous_value ~= nil and ref['on_remove'] then
            ref['on_remove'](change.previous_value, change.dynamic_index or change.field)
          end

        elseif change.op == OPERATION.DELETE_AND_ADD then
          if change.previous_value ~= nil and ref['on_remove'] then
            ref['on_remove'](change.previous_value, change.dynamic_index)
          end
          if ref['on_add'] then
            ref['on_add'](change.value, change.dynamic_index)
          end

        elseif (
          change.op == OPERATION.REPLACE or
          change.value ~= change.previous_value
        ) then
          if ref['on_change'] then
            ref['on_change'](change.value, change.dynamic_index)
          end
        end
      end

      --
      -- trigger onRemove on child structure.
      --
      if (
        bit.band(change.op, OPERATION.DELETE) == OPERATION.DELETE and
        type(change.previous_value) == "table" and
        change.previous_value['_schema'] ~= nil and
        change.previous_value['on_remove']
      ) then
        change.previous_value['on_remove']()
      end

    end

    if is_schema and ref['on_change'] then
      ref['on_change'](changes)
    end
  end
end

function Schema:get_schema_type(bytes, it, default_type)
  local schema_type = default_type;

  if (bytes[it.offset] == spec.TYPE_ID) then
    it.offset = it.offset + 1

    local type_id = decode.number(bytes, it)
    schema_type = self._context:get(type_id)
  end

  return schema_type;
end

function Schema:create_instance_type(bytes, it, typeref)
    if bytes[it.offset] == spec.TYPE_ID then
        it.offset = it.offset + 1
        local another_type = self._context:get(decode.uint8(bytes, it))
        return another_type:new()
    else
        return typeref:new()
    end
end
-- END SCHEMA CLASS --

local global_context = Context:new()
local define = function(fields, context, typeid)
    local DerivedSchema = Schema:new()

    if not context then
      context = global_context
    end

    DerivedSchema._schema = {}
    DerivedSchema._fields_by_index = fields and fields['_fields_by_index'] or {}
    DerivedSchema._context = context

    context:add(DerivedSchema, typeid)

    for i, field in pairs(DerivedSchema._fields_by_index) do
        DerivedSchema._schema[field] = fields[field]
    end

    return DerivedSchema
end

-- START REFLECTION --
local reflection_context = Context:new()
local ReflectionField = define({
    ["name"] = "string",
    ["type"] = "string",
    ["referenced_type"] = "number",
    ["_fields_by_index"] = {"name", "type", "referenced_type"}
}, reflection_context)

local ReflectionType = define({
    ["id"] = "number",
    ["fields"] = { array = ReflectionField },
    ["_fields_by_index"] = {"id", "fields"}
}, reflection_context)

local Reflection = define({
    ["types"] = { array = ReflectionType },
    ["root_type"] = "number",
    ["_fields_by_index"] = {"types", "root_type"}
}, reflection_context)

local reflection_decode = function (bytes, it)
    local context = Context:new()

    local reflection = Reflection:new()
    reflection:decode(bytes, it)

    local add_field_to_schema = function(schema_class, field_name, field_type)
        schema_class._schema[field_name] = field_type
        table.insert(schema_class._fields_by_index, field_name)
    end

    local schema_types = {}

    reflection.types:each(function(reflection_type)
        schema_types[reflection_type.id] = define({}, context, reflection_type.id)
    end)

    for i = 1, reflection.types:length() do
        local reflection_type = reflection.types[i]

        for j = 1, reflection_type.fields:length() do
            local schema_type = schema_types[reflection_type.id]
            local field = reflection_type.fields[j]

            if field.referenced_type ~= nil then
                local referenced_type = schema_types[field.referenced_type]

                if referenced_type == nil then
                    local child_type_index = string.find(field.type, ":")
                    referenced_type = string.sub(
                        field.type,
                        child_type_index + 1,
                        string.len(field.type)
                    )
                    field.type = string.sub(field.type, 1, child_type_index - 1)
                end

                if field.type == "ref" then
                    add_field_to_schema(schema_type, field.name, referenced_type)

                else
                    -- { map = referenced_type }
                    -- { array = referenced_type }
                    -- ...etc
                    add_field_to_schema(schema_type, field.name, { [field.type] = referenced_type })
                end

            else
                add_field_to_schema(schema_type, field.name, field.type)
            end
        end
    end

    local root_type = schema_types[reflection.root_type]
    local root_instance = root_type:new()

    for i = 1, #root_type._fields_by_index do
        local field_name = root_type._fields_by_index[i]
        local field_type = root_type._schema[field_name]

        if type(field_type) ~= "string" then
            -- local is_schema = field_type['new'] ~= nil
            -- local is_map = field_type['map'] ~= nil
            -- local is_array = type(field_type) == "table" and (not is_schema) and (not is_map)

            if field_type['new'] ~= nil then
                root_instance[field_name] = field_type:new()

            elseif type(field_type) == "table" then
                local collection_type_id = next(field_type)
                local collection = types.get_type(collection_type_id)
                root_instance[field_name] = collection:new()
                root_instance[field_name]._child_type = field_type[collection_type_id]
            end
        end
    end

    return root_instance
end
-- END REFLECTION --

return {
    define = define,
    reflection_decode = reflection_decode,
    decode = decode,
    encode = encode,
    pprint = pprint,
}
