-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 5.0.11
-- 

local schema = require 'colyseus.serializer.schema.schema'
local Unit = require 'test.schema.ResyncFixtures.Unit'

---@class ResyncArrayState: Schema
---@field arr ArraySchema
local ResyncArrayState = schema.define({
    ["arr"] = { array = Unit },
    ["_fields_by_index"] = { "arr" },
})

return ResyncArrayState
