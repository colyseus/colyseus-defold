--
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
--
-- GENERATED USING @colyseus/schema 1.0.0-alpha.58
--

local schema = require 'colyseus.serializer.schema.schema'
local IAmAChild = require 'test.schema.MapSchemaTypes.IAmAChild'

---@class MapSchemaTypes: Schema
---@field mapOfSchemas MapSchema
---@field mapOfNumbers MapSchema
---@field mapOfStrings MapSchema
---@field mapOfInt32 MapSchema
local MapSchemaTypes = schema.define({
    ["mapOfSchemas"] = { map = IAmAChild },
    ["mapOfNumbers"] = { map = "number" },
    ["mapOfStrings"] = { map = "string" },
    ["mapOfInt32"] = { map = "int32" },
    ["_fields_by_index"] = { "mapOfSchemas", "mapOfNumbers", "mapOfStrings", "mapOfInt32" },
})

return MapSchemaTypes
