-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 1.0.0-alpha.58
-- 

local schema = require 'colyseus.serialization.schema.schema'
local IAmAChild = require 'test.schema.ArraySchemaTypes.IAmAChild'

local ArraySchemaTypes = schema.define({
    ["arrayOfSchemas"] = { array = IAmAChild },
    ["arrayOfNumbers"] = { array = "number" },
    ["arrayOfStrings"] = { array = "string" },
    ["arrayOfInt32"] = { array = "int32" },
    ["_fields_by_index"] = { "arrayOfSchemas", "arrayOfNumbers", "arrayOfStrings", "arrayOfInt32" },
})

return ArraySchemaTypes
