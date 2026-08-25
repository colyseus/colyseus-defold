-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 5.0.11
-- 

local schema = require 'colyseus.serializer.schema.schema'


---@class ReckonBall: Schema
---@field x number
---@field vx number
local ReckonBall = schema.define({
    ["x"] = "number",
    ["vx"] = "number",
    ["_fields_by_index"] = { "x", "vx" },
})

return ReckonBall
