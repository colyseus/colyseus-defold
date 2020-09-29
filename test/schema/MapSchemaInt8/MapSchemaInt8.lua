-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 1.0.0-alpha.58
-- 

local schema = require 'colyseus.serialization.schema.schema'


local MapSchemaInt8 = schema.define({
    ["status"] = "string",
    ["mapOfInt8"] = { map = "int8" },
    ["_fields_by_index"] = { "status", "mapOfInt8" },
})

return MapSchemaInt8
