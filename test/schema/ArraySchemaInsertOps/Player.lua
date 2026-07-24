-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 5.0.11
-- 

local schema = require 'colyseus.serializer.schema.schema'


---@class Player: Schema
---@field name string
---@field x number
---@field y number
local Player = schema.define({
    ["name"] = "string",
    ["x"] = "number",
    ["y"] = "number",
    ["_fields_by_index"] = { "name", "x", "y" },
})

return Player
