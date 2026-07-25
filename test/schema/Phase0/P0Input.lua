-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 5.0.11
-- 

local schema = require 'colyseus.serializer.schema.schema'


---@class P0Input: Schema
---@field x number
---@field y number
local P0Input = schema.define({
    ["x"] = "number",
    ["y"] = "number",
    ["_fields_by_index"] = { "x", "y" },
})

return P0Input
