-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 1.0.0-alpha.58
-- 

local schema = require 'colyseus.serialization.schema.schema'
local Player = require 'test.schema.FilteredTypes.Player'

local State = schema.define({
    ["playerOne"] = Player,
    ["playerTwo"] = Player,
    ["players"] = { array = Player },
    ["_fields_by_index"] = { "playerOne", "playerTwo", "players" },
})

return State
