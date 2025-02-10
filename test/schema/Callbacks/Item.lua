--
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
--
-- GENERATED USING @colyseus/schema 3.0.0-alpha.45
--

local schema = require 'colyseus.serializer.schema.schema'


---@class Item: Schema
---@field name string
---@field value number
local Item = schema.define({
    ["name"] = "string",
    ["value"] = "number",
    ["_fields_by_index"] = { "name", "value" },
})

return Item
