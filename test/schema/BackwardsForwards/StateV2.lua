-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 0.4.61
-- 

local schema = require 'colyseus.serialization.schema.schema'
local PlayerV2 = require 'test.schema.BackwardsForwards.PlayerV2'

local StateV2 = schema.define({
    ["str"] = "string",
    ["map"] = { map = PlayerV2 },
    ["countdown"] = "number",
    ["_order"] = { "str", "map", "countdown" },

    ["on_change"] = function(changes)
        -- on change logic here
    end,

    ["on_add"] = function()
        -- on add logic here
     end,

    ["on_remove"] = function()
        -- on remove logic here
    end,
})

return StateV2
