-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 1.0.0-alpha.58
-- 

local schema = require 'colyseus.serialization.schema.schema'


local PlayerV2 = schema.define({
    ["x"] = "number",
    ["y"] = "number",
    ["name"] = "string",
    ["arrayOfStrings"] = { array = "string" },
    ["_fields_by_index"] = { "x", "y", "name", "arrayOfStrings" },
})

return PlayerV2
