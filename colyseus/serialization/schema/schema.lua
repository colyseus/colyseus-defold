local types = require 'colyseus.serialization.schema.types'

local constants = require 'colyseus.serialization.schema.constants'
local SPEC = constants.SPEC;

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

---@class Schema
---@field _schema table
---@field _fields_by_index table
local Schema = {}

function Schema:new(obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self

    --
    -- TODO: remove this
    --

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

function Schema:set_by_index(field_index, dynamic_index, value)
  self[self._fields_by_index[field_index]] = value
end

function Schema:get_by_index(field_index)
  return self[self._fields_by_index[field_index]]
end

function Schema:delete_by_index(field_index)
  self[self._fields_by_index[field_index]] = nil
end

function Schema:to_raw()
  local raw = {}

  for field, _ in pairs(self._schema) do
    if type(self[field]) == "table" and type(self[field]['to_raw']) == "function" then
      raw[field] = self[field]:to_raw()
    else
      raw[field] = self[field]
    end
  end

  return raw
end

-- END SCHEMA CLASS --

---@param fields table
---@param extends Schema|nil
local define = function(fields, extends)
    local schemaClass = Schema:new()
    schemaClass._schema = {}

    local fields_by_index = {}

    if extends ~= nil and extends._fields_by_index ~= nil then
      for _, field in pairs(extends._fields_by_index) do
          fields[field] = extends._schema[field]
          table.insert(fields_by_index, field)
      end
      schemaClass.__index = extends
    end

    if fields._fields_by_index ~= nil then
      for _, field in pairs(fields._fields_by_index) do
        table.insert(fields_by_index, field)
        schemaClass._schema[field] = fields[field]
      end
    end

    schemaClass._fields_by_index = fields_by_index

    return schemaClass
end

return {
  define = define,
  Schema = Schema,
}
