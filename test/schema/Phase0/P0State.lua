-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 5.0.11
-- 

local schema = require 'colyseus.serializer.schema.schema'


---@class P0State: Schema
---@field msg string
---@field n number
local P0State = schema.define({
    ["msg"] = "string",
    ["n"] = "number",
    ["_fields_by_index"] = { "msg", "n" },
})

return P0State
