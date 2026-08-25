-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 5.0.11
-- 

local schema = require 'colyseus.serializer.schema.schema'


---@class ResyncPlayerV1: Schema
---@field x number
local ResyncPlayerV1 = schema.define({
    ["x"] = "number",
    ["_fields_by_index"] = { "x" },
})

return ResyncPlayerV1
