-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 0.4.61
-- 

local schema = require 'colyseus.serialization.schema.schema'
local IAmAChild = require 'test.schema.ArraySchemaTypes.IAmAChild'

local ArraySchemaTypes = schema.define({
    ["arrayOfSchemas"] = { IAmAChild },
    ["arrayOfNumbers"] = { "number" },
    ["arrayOfStrings"] = { "string" },
    ["arrayOfInt32"] = { "int32" },
    ["_order"] = { "arrayOfSchemas", "arrayOfNumbers", "arrayOfStrings", "arrayOfInt32" },

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

return ArraySchemaTypes
