-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 5.0.11
-- 

local schema = require 'colyseus.serializer.schema.schema'


---@class PassiveEnt: Schema
---@field a number
---@field b number
---@field c number
---@field d number
---@field yaw number
local PassiveEnt = schema.define({
    ["a"] = "number",
    ["b"] = "number",
    ["c"] = "number",
    ["d"] = "number",
    ["yaw"] = "number",
    ["_fields_by_index"] = { "a", "b", "c", "d", "yaw" },
})

return PassiveEnt
