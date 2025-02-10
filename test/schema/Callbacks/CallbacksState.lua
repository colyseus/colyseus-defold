--
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
--
-- GENERATED USING @colyseus/schema 3.0.0-alpha.45
--

local schema = require 'colyseus.serializer.schema.schema'
local Container = require 'test.schema.Callbacks.Container'

---@class CallbacksState: Schema
---@field container Container
local CallbacksState = schema.define({
    ["container"] = Container,
    ["_fields_by_index"] = { "container" },
})

return CallbacksState
