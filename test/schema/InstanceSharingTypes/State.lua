-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 1.0.0-alpha.58
-- 

local schema = require 'colyseus.serialization.schema.schema'
local Player = require 'test.schema.InstanceSharingTypes.Player'

local State = schema.define({
    ["player1"] = Player,
    ["player2"] = Player,
    ["arrayOfPlayers"] = { array = Player },
    ["mapOfPlayers"] = { map = Player },
    ["_fields_by_index"] = { "player1", "player2", "arrayOfPlayers", "mapOfPlayers" },
})

return State
