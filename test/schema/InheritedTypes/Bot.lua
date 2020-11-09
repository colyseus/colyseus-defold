-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 1.0.0-alpha.58
-- 

local schema = require 'colyseus.serialization.schema.schema'
local Player = require 'test.schema.InheritedTypes.Player'
local Entity = require 'test.schema.InheritedTypes.Entity'

local Bot = schema.define({
    ["power"] = "number",
    ["_fields_by_index"] = { "power" },
})

return Bot
