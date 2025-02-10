--
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
--
-- GENERATED USING @colyseus/schema 3.0.0-alpha.45
--

local schema = require 'colyseus.serializer.schema.schema'
local Player = require 'test.schema.Callbacks.Player'

---@class Container: Schema
---@field playersMap MapSchema
local Container = schema.define({
    ["playersMap"] = { map = Player },
    ["_fields_by_index"] = { "playersMap" },
})

return Container
