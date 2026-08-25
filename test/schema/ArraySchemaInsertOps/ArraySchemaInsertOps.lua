-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 5.0.11
-- 

local schema = require 'colyseus.serializer.schema.schema'
local Item = require 'test.schema.ArraySchemaInsertOps.Item'
local Player = require 'test.schema.ArraySchemaInsertOps.Player'

---@class ArraySchemaInsertOps: Schema
---@field numbers ArraySchema
---@field items ArraySchema
---@field players ArraySchema
local ArraySchemaInsertOps = schema.define({
    ["numbers"] = { array = "number" },
    ["items"] = { array = Item },
    ["players"] = { array = Player },
    ["_fields_by_index"] = { "numbers", "items", "players" },
})

return ArraySchemaInsertOps
