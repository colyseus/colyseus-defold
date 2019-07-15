--
-- @colyseus/schema decoder for LUA
-- Do not modify this file unless you know exactly what you're doing.
--
-- This file is part of Colyseus: https://github.com/colyseus/colyseus
--
local bit = require 'colyseus.serialization.bit'
local ldexp = math.ldexp or mathx.ldexp

-- START SPEC --
local spec = {
    END_OF_STRUCTURE = 193,
    NIL = 192,
    INDEX_CHANGE = 212,
    TYPE_ID = 213,
}
-- END SPEC --

-- START DECODE --
function utf8_read(bytes, offset, length)
  local str = ""
  local chr = 0

  local len = offset + length

  for i = offset, len - 1 do
    repeat
        local byte = bytes[i]

        if (bit.band(byte, 0x80) == 0x00) then
            str = str .. string.char(byte)
            break
        end

        if (bit.band(byte, 0xe0) == 0xc0) then
            local b1 = bytes[i]
            i = i + 1

            str = str .. string.char(
                bit.bor(
                    bit.arshift(bit.band(byte, 0x1f), 6),
                    bit.band(bytes[b1], 0x3f)
                )
            )
            break
        end

        if (bit.band(byte, 0xf0) == 0xe0) then
            local b1 = bytes[i]
            i = i + 1
            local b2 = bytes[i]
            i = i + 1

            str = str .. string.char(
                bit.bor(
                    bit.arshift(bit.band(byte, 0x0f), 12),
                    bit.arshift(bit.band(bytes[b1], 0x3f), 6),
                    bit.arshift(bit.band(bytes[b2], 0x3f), 0)
                )
            )
            break
        end

        if (bit.band(byte, 0xf8) == 0xf0) then
            local b1 = bytes[i]
            i = i + 1
            local b2 = bytes[i]
            i = i + 1
            local b3 = bytes[i]
            i = i + 1

            chr = bit.bor(
                bit.arshift(bit.band(byte, 0x07), 18),
                bit.arshift(bit.band(bytes[b1], 0x3f), 12),
                bit.arshift(bit.band(bytes[b2], 0x3f), 6),
                bit.arshift(bit.band(bytes[b3], 0x3f), 0)
            )
            if (chr >= 0x010000) then -- surrogate pair
                chr = chr - 0x010000
                error("not supported string!" .. tostring(chr))
                -- str = str .. str.char((chr >>> 10) + 0xD800, bit.band(chr, 0x3FF) + 0xDC00)
            else
                str = str .. string.char(chr)
            end
            break
        end

        pprint(str)
        error('invalid byte ' .. byte)
        break
    until true
  end

  return str
end

function bit_logic_rshift(n, bits)
    if(n <= 0) then
        n = bit.bnot(math.abs(n)) + 1
    end
    for i=1, bits do
        n = n/2
    end
    return math.floor(n)
end

function bit_rshift(value, n)
    local r = bit.rshift(value, n)

    if r < 0 and n == 0 then
        return bit.rshift(r, 1) * 2
    else
        return r
    end
end

function boolean (bytes, it)
    return uint8(bytes, it) == 1
end

function int8 (bytes, it)
    return bit.arshift(bit.lshift(uint8(bytes, it), 24), 24)
end

function uint8 (bytes, it)
    local int = bytes[it.offset]
    it.offset = it.offset + 1
    return int
end

function int16 (bytes, it)
    return bit.arshift(bit.lshift(uint16(bytes, it), 16), 16)
end

function uint16 (bytes, it)
    local n1 = bytes[it.offset]
    it.offset = it.offset + 1

    local n2 = bytes[it.offset]
    it.offset = it.offset + 1

    return bit.bor(n1, bit.lshift(n2, 8))
end

function int32 (bytes, it)
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

function uint32 (bytes, it)
    local b4 = bytes[it.offset]
    local b3 = bytes[it.offset + 1]
    local b2 = bytes[it.offset + 2]
    local b1 = bytes[it.offset + 3]
    it.offset = it.offset + 4
    return ((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4
end

function int64 (bytes, it)
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

function uint64 (bytes, it)
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

function float32(bytes, it)
    local b1 = bytes[it.offset]
    local b2 = bytes[it.offset + 1]
    local b3 = bytes[it.offset + 2]
    local b4 = bytes[it.offset + 3]
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
            n = sign * huge
        else
            n = 0.0/0.0
        end
    else
        n = sign * ldexp(1.0 + mant / 0x800000, expo - 0x7F)
    end
    it.offset = it.offset + 4
    return n
end

function float64(bytes, it)
    local b1 = bytes[it.offset + 7]
    local b2 = bytes[it.offset + 6]
    local b3 = bytes[it.offset + 5]
    local b4 = bytes[it.offset + 4]
    local b5 = bytes[it.offset + 3]
    local b6 = bytes[it.offset + 2]
    local b7 = bytes[it.offset + 1]
    local b8 = bytes[it.offset]

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
            n = sign * huge
        else
            n = 0.0/0.0
        end
    else
        n = sign * ldexp(1.0 + mant / 4503599627370496.0, expo - 0x3FF)
    end
    it.offset = it.offset + 8
    return n
end

function _string (bytes, it)
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

function string_check (bytes, it)
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

function number (bytes, it)
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

function number_check (bytes, it)
  local prefix = bytes[it.offset]
  return (prefix < 128 or (prefix >= 202 and prefix <= 211))
end

function array_check (bytes, it)
  return bytes[it.offset] < 160
end

function nil_check (bytes, it)
  return bytes[it.offset] == spec.NIL
end

function index_change_check (bytes, it)
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

function decode_primitive_type (ftype, bytes, it)
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

-- START MAP SCHEMA
local MapSchema = {}
function MapSchema:new(obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function MapSchema:trigger_all()
    if type(self) ~= "table" or self['on_add'] == nil then return end
    for key, value in pairs(self) do
        if key ~= 'on_add' and key ~= 'on_remove' and key ~= 'on_change' then
            self['on_add'](value, key)
        end
    end
end

function MapSchema:clone()
    local cloned = MapSchema:new(table.clone(self))
    cloned['on_add'] = self['on_add']
    cloned['on_remove'] = self['on_remove']
    cloned['on_change'] = self['on_change']
    return cloned
end
-- END MAP SCHEMA

-- START ARRAY SCHEMA
local ArraySchema = {}
function ArraySchema:new(obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function ArraySchema:trigger_all()
    if type(self) ~= "table" or self['on_add'] == nil then return end
    for key, value in ipairs(self) do
        if key ~= 'on_add' and key ~= 'on_remove' and key ~= 'on_change' then
            self['on_add'](value, key)
        end
    end
end

function ArraySchema:clone()
    local cloned = ArraySchema:new(table.clone(self))
    cloned['on_add'] = self['on_add']
    cloned['on_remove'] = self['on_remove']
    cloned['on_change'] = self['on_change']
    return cloned
end
-- END ARRAY SCHEMA

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

function Schema:decode(bytes, it)
    local changes = {}

    if it == nil then
        it = { offset = 1 }
    end

    local schema = self._schema
    local fields_by_index = self._order

    -- skip TYPE_ID of existing instances
    if bytes[it.offset] == spec.TYPE_ID then
        it.offset = it.offset + 2
    end

    local total_bytes = #bytes
    while it.offset <= total_bytes do
        local index = bytes[it.offset]
        it.offset = it.offset + 1

        -- reached end of strucutre. skip.
        if index == spec.END_OF_STRUCTURE then
            -- print("END_OF_STRUCTURE, breaking at offset:", it.offset)
            break
        end

        local field = fields_by_index[index + 1]
        local ftype = schema[field]
        local value = nil

        local change = nil
        local has_change = false

        -- FIXME: this may cause issues if the `index` provided actually matches a field.
        -- WORKAROUND for LUA on emscripten environment
        -- (reached end of buffer)
        if not field then
            -- print("FIELD NOT FOUND, byte =>", index, ", previous byte =>", bytes[it.offset - 2])
            it.offset = it.offset - 1
            break
        end

        if type(ftype) == "table" and ftype['new'] ~= nil then
            if decode.nil_check(bytes, it) then
                it.offset = it.offset + 1
                value = nil
            else
                -- decode child Schema instance
                value = self[field] or self:create_instance_type(bytes, it, ftype)
                value:decode(bytes, it)
                has_change = true
            end

        elseif type(ftype) == "table" and ftype['map'] == nil then
            -- decode array
            local typeref = ftype[1]
            change = {}

            local value_ref = self[field] or ArraySchema:new()
            value = value_ref:clone() -- create new reference for array


            local new_length = decode.number(bytes, it)
            local num_changes = math.min(decode.number(bytes, it), new_length)

            has_change = (num_changes > 0)

            -- FIXME: this may not be reliable. possibly need to encode this variable during
            -- serialization
            local has_index_change = false

            -- ensure current array has the same length as encoded one
            if #value >= new_length then
                local new_values = ArraySchema:new()
                new_values['on_add'] = value_ref['on_add']
                new_values['on_remove'] = value_ref['on_remove']
                new_values['on_change'] = value_ref['on_change']

                for i, item in ipairs(value) do
                    if i > new_length then
                        -- call "on_removed" on exceeding items
                        if type(item) == "table" and item["on_remove"] ~= nil then
                            item["on_remove"]()
                        end

                        -- call on_remove from ArraySchema
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

                        if decode.nil_check(bytes, it) then
                            it.offset = it.offset + 1

                            -- call on_remove from ArraySchema
                            if value_ref['on_remove'] ~= nil then
                                value_ref['on_remove'](item, new_index)
                            end

                            break -- continue
                        end

                        item:decode(bytes, it)
                        value[new_index] = item

                    else
                        value[new_index] = decode_primitive_type(typeref, bytes, it)
                    end

                    -- add on_add from ArraySchema
                    if is_new then
                        if value_ref['on_add'] ~= nil then
                            value_ref['on_add'](value[new_index], new_index)
                        end

                    elseif value_ref['on_change'] ~= nil then
                        value_ref['on_change'](value[new_index], new_index)
                    end

                    table.insert(change, value[new_index])

                    break -- continue
                until true

                -- workaround because lack of `continue` statement in LUA
                if break_outer_loop then break end

                i = i + 1
            end

        elseif type(ftype) == "table" and ftype['map'] ~= nil then
            -- decode map
            local typeref = ftype['map']

            local maporder_key = "_" .. field .. "_maporder"
            local value_ref = self[field] or MapSchema:new()
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

                    -- index change check
                    local previous_key
                    if decode.index_change_check(bytes, it) then
                        decode.uint8(bytes, it)
                        previous_key = self[maporder_key][decode.number(bytes, it)+1]
                        has_index_change = true
                    end

                    local has_map_index = decode.number_check(bytes, it)
                    local is_schema_type = type(typeref) ~= "string";

                    local new_key
                    local map_index
                    if has_map_index then
                        map_index = decode.number(bytes, it) + 1
                        new_key = self[maporder_key][map_index]
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

                    if decode.nil_check(bytes, it) then
                        it.offset = it.offset + 1

                        if item ~= nil and type(item) == "table" and item['on_remove'] ~= nil then
                            item['on_remove']()
                        end

                        if value_ref['on_remove'] ~= nil then
                            value_ref['on_remove'](item, new_key)
                        end

                        value[new_key] = nil
                        table.remove(self[maporder_key], map_index)
                        break -- continue

                    elseif not is_schema_type then
                        value[new_key] = decode_primitive_type(typeref, bytes, it)

                    else
                        item:decode(bytes, it)
                        value[new_key] = item
                    end

                    if is_new then
                        if value_ref['on_add'] ~= nil then
                            value_ref['on_add'](value[new_key], new_key)
                        end

                    elseif value_ref['on_change'] ~= nil then
                        value_ref['on_change'](value[new_key], new_key)
                    end

                    if is_new then
                        -- LUA-specific keep track of keys ordering (lua tables doesn't keep then)
                        if self[maporder_key] == nil then
                            self[maporder_key] = {}
                        end
                        table.insert(self[maporder_key], new_key)
                        --
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
                value = change or value,
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

    DerivedSchema._schema = {}
    DerivedSchema._order = fields and fields['_order'] or {}
    DerivedSchema._context = context or global_context

    context:add(DerivedSchema, typeid)

    for i, field in pairs(DerivedSchema._order) do
        DerivedSchema._schema[field] = fields[field]
    end

    return DerivedSchema
end

-- START REFLECTION --
local reflection_context = Context:new()
local ReflectionField = define({
    ["name"] = "string",
    ["type"] = "string",
    ["referenced_type"] = "uint8",
    ["_order"] = {"name", "type", "referenced_type"}
}, reflection_context)

local ReflectionType = define({
    ["id"] = "uint8",
    ["fields"] = { ReflectionField },
    ["_order"] = {"id", "fields"}
}, reflection_context)

local Reflection = define({
    ["types"] = { ReflectionType },
    ["root_type"] = "uint8",
    ["_order"] = {"types", "root_type"}
}, reflection_context)

local reflection_decode = function (bytes, it)
    local context = Context:new()

    local reflection = Reflection:new()
    reflection:decode(bytes, it)

    local add_field_to_schema = function(schema_class, field_name, field_type)
        schema_class._schema[field_name] = field_type
        table.insert(schema_class._order, field_name)
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

    for i = 1, #root_type._order do
        local field_name = root_type._order[i]
        local field_type = root_type._schema[field_name]

        if type(field_type) ~= "string" then
            -- local is_schema = field_type['new'] ~= nil
            -- local is_map = field_type['map'] ~= nil
            -- local is_array = type(field_type) == "table" and (not is_schema) and (not is_map)

            if field_type['new'] ~= nil then
                root_instance[field_name] = field_type:new()

            elseif type(field_type) == "table" then
                if field_type.map ~= nil then
                    root_instance[field_name] = MapSchema:new()
                else
                    root_instance[field_name] = ArraySchema:new()
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
    string = decode.string,
    pprint = pprint
}
