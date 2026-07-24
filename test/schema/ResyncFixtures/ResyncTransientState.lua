-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 5.0.11
-- 

local schema = require 'colyseus.serializer.schema.schema'
local Unit = require 'test.schema.ResyncFixtures.Unit'

---@class ResyncTransientState: Schema
---@field units MapSchema
---@field locals MapSchema
local ResyncTransientState = schema.define({
    ["units"] = { map = Unit },
    ["locals"] = { map = "number" },
    ["_fields_by_index"] = { "units", "locals" },
})

return ResyncTransientState
