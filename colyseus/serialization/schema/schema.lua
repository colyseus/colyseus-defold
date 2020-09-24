--
-- @colyseus/schema decoder for LUA
-- Do not modify this file unless you know exactly what you're doing.
--
-- This file is part of Colyseus: https://github.com/colyseus/colyseus
--
local bit = require 'colyseus.serialization.bit'
local ldexp = math.ldexp or mathx.ldexp

local array_schema = require 'colyseus.serialization.schema.array_schema'
local map_schema = require 'colyseus.serialization.schema.map_schema'
local reference_tracker = require 'colyseus.serialization.schema.reference_tracker'

-- START SPEC + OPERATION --
local spec = {
    SWITCH_TO_STRUCTURE = 255,
    TYPE_ID = 213,
}

local OPERATION = {
  -- add new structure/primitive
  ADD = 128,

  -- replace structure/primitive
  REPLACE = 0,

  -- delete field
  DELETE = 64,

  -- DELETE field, followed by an ADD
  DELETE_AND_ADD = 192,

  -- TOUCH is used to determine hierarchy of nested Schema structures during serialization.
  -- touches are NOT encoded.
  TOUCH = 1,

  -- MapSchema Operations
  CLEAR = 10,
}
-- END SPEC + OPERATION --

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

local function nil_check (bytes, it)
  return bytes[it.offset] == spec.NIL
end

local function index_change_check (bytes, it)
  return bytes[it.offset] == spec.INDEX_CHANGE
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
    nil_check = nil_check,
    index_change_check = index_change_check,
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

local function decode_primitive_type (ftype, bytes, it)
    local func = decode[ftype]
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
    return obj
end

function Schema:trigger_all()
    -- skip if 'on_change' is not set
    if self['on_change'] == nil then return end

    local changes = {}
    for field, _ in pairs(self._schema) do
        if self[field] ~= nil then
            table.insert(changes, {
                field = field,
                value = self[field],
                previous_value = nil
            })
        end
    end

    self['on_change'](changes)
end

function Schema:decode(bytes, it, refs)
    -- default iterator
    if it == nil then it = { offset = 1 } end

    -- default reference tracker
    if refs == nil then refs = reference_tracker:new() end

    local ref_id = 0
    local ref = self

    local changes = {}
    local all_changes = {}

    refs:set(ref_id, ref)
    all_changes[ref_id] = changes

    -- local schema = self._schema
    -- local fields_by_index = self._fields_by_index

    -- -- skip TYPE_ID of existing instances
    -- if bytes[it.offset] == spec.TYPE_ID then
    --     it.offset = it.offset + 2
    -- end

    local total_bytes = #bytes
    while it.offset <= total_bytes do
        local byte = bytes[it.offset]
        it.offset = it.offset + 1

        if byte == spec.SWITCH_TO_STRUCTURE then
            -- LUA "continue" workaround.
            -- (repeat/until + break)
            repeat
                ref_id = decode.number(bytes, it)

                local next_ref = refs:get(ref_id)

                --
                -- Trying to access a reference that haven't been decoded yet.
                --
                if next_ref == nil then error('"refId" not found: ' .. ref_id) end

                ref = next_ref

                -- create empty list of changes for this refId.
                changes = {}
                all_changes[ref_id] = changes

                break -- continue
            until true
        end

        local is_schema = (ref._schema ~= nil) and true or false

        --
        -- index operation
        -- compressed: index + operation -> (byte >> 6) << 6
        -- uncompressed: index -> byte
        --
        local operation = (is_schema) and (bit.arshift(bit.lshift(byte, 6), 6)) or byte

        if operation == OPERATION.CLEAR then
          --
          -- TODO: refactor me!
          -- The `.clear()` method is calling `$root.removeRef(refId)` for
          -- each item inside this collection
          --
          ref:clear()
          continue;
        end

        local field_index = (is_schema)
          and (byte % (operation || 255))
          or decode.number(bytes, it)

        local field_name = (is_schema)
          and ref._fields_by_index[field_index + 1]
          or nil

        -- TODO: get type from parent structure if `ref` is a collection.
        local ftype = ref._schema[field_name]

        local value
        local previous_value

        local dynamic_index

        if not is_schema then
        else
        end

        --
        -- FIXME: this may cause issues if the `index` provided actually matches a field.
        --
        -- WORKAROUND for LUA on emscripten environment
        --   End of buffer has been probably reached.
        --   Revert an offset, as a new message may be next to it.
        --
        if not field then
          print("DANGER: invalid field found at index:", index," - skipping patch data after offset:", it.offset)
          it.offset = it.offset - 1
          break
        end

        if is_nil then
            value = nil
            has_change = true

        elseif type(ftype) == "table" and ftype['new'] ~= nil then
            -- decode child Schema instance
            value = self[field] or self:create_instance_type(bytes, it, ftype)
            value:decode(bytes, it)
            has_change = true

        elseif type(ftype) == "table" and ftype['map'] == nil then
            -- decode array
            local typeref = ftype[1]

            local value_ref = self[field] or array_schema:new()
            value = value_ref:clone() -- create new reference for array

            local new_length = decode.number(bytes, it)
            local num_changes = math.min(decode.number(bytes, it), new_length)

            local has_removal = (#value >= new_length)
            has_change = (num_changes > 0) or has_removal

            -- FIXME: this may not be reliable. possibly need to encode this variable during
            -- serialization
            local has_index_change = false

            -- ensure current array has the same length as encoded one
            if has_removal then
                local new_values = array_schema:new()
                new_values['on_add'] = value_ref['on_add']
                new_values['on_remove'] = value_ref['on_remove']
                new_values['on_change'] = value_ref['on_change']

                for i, item in ipairs(value) do
                    if i > new_length then
                        -- call "on_removed" on exceeding items
                        if type(item) == "table" and item["on_remove"] ~= nil then
                            item["on_remove"]()
                        end

                        -- call on_remove from array_schema
                        if value_ref["on_remove"] ~= nil then
                            value_ref["on_remove"](item, i)
                        end
                    else
                        table.insert(new_values, item)
                    end
                end

                value = new_values
            end

            local i = 0
            while i < num_changes do
                local new_index = decode.number(bytes, it)

                -- lua indexes start at 1
                if new_index ~= nil then
                    new_index = new_index + 1
                end
                --

                -- index change check
                local index_change_from
                if (decode.index_change_check(bytes, it)) then
                    decode.uint8(bytes, it)
                    index_change_from = decode.number(bytes, it) + 1
                    has_index_change = true
                end

                local is_new = (not has_index_change and not value[new_index]) or (has_index_change and index_change_from == nil);

                -- LUA: do/end block is necessary due to `break`
                -- workaround because lack of `continue` statement in LUA
                local break_outer_loop = false
                repeat
                    if typeref['new'] ~= nil then -- is instance of Schema
                        local item

                        if has_index_change and index_change_from == nil and new_index ~= nil then
                            item = self:create_instance_type(bytes, it, typeref)

                        elseif (index_change_from ~= nil) then
                            item = value_ref[index_change_from]

                        elseif (new_index ~= nil) then
                            item = value_ref[new_index]
                        end

                        if item == nil then
                            item = self:create_instance_type(bytes, it, typeref)
                            is_new = true
                        end

                        item:decode(bytes, it)
                        value[new_index] = item

                    else
                        value[new_index] = decode_primitive_type(typeref, bytes, it)
                    end

                    -- add on_add from array_schema
                    if is_new then
                        if value_ref['on_add'] ~= nil then
                            value_ref['on_add'](value[new_index], new_index)
                        end

                    elseif value_ref['on_change'] ~= nil then
                        value_ref['on_change'](value[new_index], new_index)
                    end

                    break -- continue
                until true

                -- workaround because lack of `continue` statement in LUA
                if break_outer_loop then break end

                i = i + 1
            end

        elseif type(ftype) == "table" and ftype['map'] ~= nil then
            -- decode map
            local typeref = ftype['map']

            local value_ref = self[field] or map_schema:new()
            value = value_ref:clone()

            local length = decode.number(bytes, it)
            has_change = (length > 0)

            -- FIXME: this may not be reliable. possibly need to encode this variable during
            -- serializagion
            local has_index_change = false

            local i = 0
            while i < length do
                local break_outer_loop = false
                repeat
                    -- `encodeAll` may indicate a higher number of indexes it actually encodes
                    if bytes[it.offset] == nil or bytes[it.offset] == spec.END_OF_STRUCTURE then
                        break_outer_loop = true
                        break -- continue
                    end

                    local is_nil_item = decode.nil_check(bytes, it)
                    if is_nil_item then it.offset = it.offset + 1 end

                    -- index change check
                    local previous_key
                    if decode.index_change_check(bytes, it) then
                        decode.uint8(bytes, it)
                        previous_key = value.__keys[decode.number(bytes, it)+1]
                        has_index_change = true
                    end

                    local has_map_index = decode.number_check(bytes, it)
                    local is_schema_type = type(typeref) ~= "string";

                    local new_key
                    local map_index
                    if has_map_index then
                        map_index = decode.number(bytes, it) + 1
                        new_key = value_ref.__keys[map_index]
                    else
                        new_key = decode.string(bytes, it)
                    end

                    local item
                    local is_new = (not has_index_change and not value_ref[new_key]) or (has_index_change and previous_key == nil and has_map_index)

                    if is_new and is_schema_type then
                        item = self:create_instance_type(bytes, it, typeref)

                    elseif previous_key ~= nil then
                        item = value_ref[previous_key]

                    else
                        item = value_ref[new_key]
                    end

                    if is_nil_item then
                        if item ~= nil and type(item) == "table" and item['on_remove'] ~= nil then
                            item['on_remove']()
                        end

                        if value_ref['on_remove'] ~= nil then
                            value_ref['on_remove'](item, new_key)
                        end

                        value:set(new_key, nil)
                        break -- continue

                    elseif not is_schema_type then
                        value:set(new_key, decode_primitive_type(typeref, bytes, it))

                    else
                        value:set(new_key, item:decode(bytes, it))
                    end

                    if is_new then
                        if value_ref['on_add'] ~= nil then
                            value_ref['on_add'](value[new_key], new_key)
                        end

                    elseif value_ref['on_change'] ~= nil then
                        value_ref['on_change'](value[new_key], new_key)
                    end

                    break -- continue
                until true

                if break_outer_loop then break end

                i = i + 1
            end

        else
            -- decode primivite type
            value = decode_primitive_type(ftype, bytes, it)
            has_change = true
        end

        if self["on_change"] and has_change then
            table.insert(changes, {
                field = field,
                value = value,
                previous_value = self[field]
            })
        end

        self[field] = value
    end

    if self["on_change"] ~= nil and table.getn(changes) then
        self["on_change"](changes)
    end

    return self
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
    ["fields"] = { ReflectionField },
    ["_fields_by_index"] = {"id", "fields"}
}, reflection_context)

local Reflection = define({
    ["types"] = { ReflectionType },
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

    for i, reflection_type in ipairs(reflection.types) do
        schema_types[reflection_type.id] = define({}, context, reflection_type.id)
    end

    for i = 1, #reflection.types do
        local reflection_type = reflection.types[i]

        for j = 1, #reflection_type.fields do
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

                if field.type == "array" then
                    add_field_to_schema(schema_type, field.name, { referenced_type })

                elseif field.type == "map" then
                    add_field_to_schema(schema_type, field.name, { map = referenced_type })

                elseif field.type == "ref" then
                    add_field_to_schema(schema_type, field.name, referenced_type)
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
                if field_type.map ~= nil then
                    root_instance[field_name] = map_schema:new()
                else
                    root_instance[field_name] = array_schema:new()
                end
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
    pprint = pprint
}
