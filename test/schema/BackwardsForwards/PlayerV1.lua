--
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
--
-- GENERATED USING @colyseus/schema 1.0.0-alpha.58
--

local schema = require 'colyseus.serializer.schema.schema'


local PlayerV1 = schema.define({
    ["x"] = "number",
    ["y"] = "number",
    ["_fields_by_index"] = { "x", "y" },
})

return PlayerV1
