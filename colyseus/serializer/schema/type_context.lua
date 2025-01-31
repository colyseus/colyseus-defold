
---@class type_context
---@field types table
---@field schemas table
local type_context = {}

function type_context:new(obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self
    obj.schemas = {}
    obj.types = {}
    return obj
end

function type_context:get(typeid)
    return self.types[typeid]
end

function type_context:add(schema, typeid)
    schema._typeid = typeid or #self.schemas
    self.types[schema._typeid] = schema
    table.insert(self.schemas, schema)
end

return type_context