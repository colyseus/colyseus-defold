-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 5.0.11
-- 

local schema = require 'colyseus.serializer.schema.schema'
local ResyncPlayerV1 = require 'test.schema.ResyncFixtures.ResyncPlayerV1'

---@class ResyncStateV1: Schema
---@field players MapSchema
local ResyncStateV1 = schema.define({
    ["players"] = { map = ResyncPlayerV1 },
    ["_fields_by_index"] = { "players" },
})

return ResyncStateV1
