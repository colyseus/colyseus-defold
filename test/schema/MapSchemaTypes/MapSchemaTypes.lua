-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 0.4.61
-- 

local schema = require 'colyseus.serialization.schema.schema'
local IAmAChild = require 'test.schema.MapSchemaTypes.IAmAChild'

local MapSchemaTypes = schema.define({
    ["mapOfSchemas"] = { map = IAmAChild },
    ["mapOfNumbers"] = { map = "number" },
    ["mapOfStrings"] = { map = "string" },
    ["mapOfInt32"] = { map = "int32" },
    ["_order"] = { "mapOfSchemas", "mapOfNumbers", "mapOfStrings", "mapOfInt32" },

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

return MapSchemaTypes
