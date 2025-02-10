--
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
--
-- GENERATED USING @colyseus/schema 3.0.0-alpha.45
--

local schema = require 'colyseus.serializer.schema.schema'
local Vec3 = require 'test.schema.Callbacks.Vec3'
local Item = require 'test.schema.Callbacks.Item'

---@class Player: Schema
---@field position Vec3
---@field items MapSchema
local Player = schema.define({
    ["position"] = Vec3,
    ["items"] = { map = Item },
    ["_fields_by_index"] = { "position", "items" },
})

return Player
