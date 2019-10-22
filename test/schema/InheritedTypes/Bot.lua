-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 0.4.61
-- 

local schema = require 'colyseus.serialization.schema.schema'
local Player = require 'test.schema.InheritedTypes.Player'
local Entity = require 'test.schema.InheritedTypes.Entity'

local Bot = schema.define({
    ["power"] = "number",
    ["_order"] = { "power" },

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

return Bot
