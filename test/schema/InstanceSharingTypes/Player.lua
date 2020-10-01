-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 1.0.0-alpha.58
-- 

local schema = require 'colyseus.serialization.schema.schema'
local Position = require 'test.schema.InstanceSharingTypes.Position'

local Player = schema.define({
    ["position"] = Position,
    ["_fields_by_index"] = { "position" },
})

return Player
