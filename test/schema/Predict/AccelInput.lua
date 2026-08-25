-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 5.0.11
-- 

local schema = require 'colyseus.serializer.schema.schema'


---@class AccelInput: Schema
---@field ax number
local AccelInput = schema.define({
    ["ax"] = "number",
    ["_fields_by_index"] = { "ax" },
})

return AccelInput
