--
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
--
-- GENERATED USING @colyseus/schema 3.0.0-alpha.42
--

local schema = require 'colyseus.serializer.schema.schema'
local Entity = require 'test.schema.InheritedTypes.Entity'

local Player = schema.define({
    ["name"] = "string",
    ["_fields_by_index"] = { "name" },
}, Entity)

return Player
