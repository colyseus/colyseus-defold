-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 5.0.11
-- 

local schema = require 'colyseus.serializer.schema.schema'
local Gem = require 'test.schema.ResyncFixtures.Gem'

---@class Unit: Schema
---@field name string
---@field hp number
---@field gems ArraySchema
local Unit = schema.define({
    ["name"] = "string",
    ["hp"] = "number",
    ["gems"] = { array = Gem },
    ["_fields_by_index"] = { "name", "hp", "gems" },
})

return Unit
