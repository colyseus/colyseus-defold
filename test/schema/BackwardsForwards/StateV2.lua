-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 1.0.0-alpha.58
-- 

local schema = require 'colyseus.serialization.schema.schema'
local PlayerV2 = require 'test.schema.BackwardsForwards.PlayerV2'

local StateV2 = schema.define({
    ["str"] = "string",
    ["map"] = { map = PlayerV2 },
    ["countdown"] = "number",
    ["_fields_by_index"] = { "str", "map", "countdown" },
})

return StateV2
