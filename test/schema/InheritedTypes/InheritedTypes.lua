-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 1.0.0-alpha.58
-- 

local schema = require 'colyseus.serialization.schema.schema'
local Entity = require 'test.schema.InheritedTypes.Entity'
local Player = require 'test.schema.InheritedTypes.Player'
local Bot = require 'test.schema.InheritedTypes.Bot'

local InheritedTypes = schema.define({
    ["entity"] = Entity,
    ["player"] = Player,
    ["bot"] = Bot,
    ["any"] = Entity,
    ["_fields_by_index"] = { "entity", "player", "bot", "any" },
})

return InheritedTypes
