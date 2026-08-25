-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 5.0.11
-- 

local schema = require 'colyseus.serializer.schema.schema'
local quantize = require 'colyseus.serializer.schema.quantize'
local QChild = require 'test.schema.Quantized.QChild'

---@class QState: Schema
---@field yaw number
---@field pitch number
---@field precise number
---@field nums ArraySchema
---@field tags MapSchema
---@field child QChild
---@field items ArraySchema
---@field label string
local QState = schema.define({
    ["yaw"] = { quantized = quantize.resolve({ min = 0, max = 6.283185307179586, bits = 16, mode = 1 }) },
    ["pitch"] = { quantized = quantize.resolve({ min = -1.5, max = 1.5, bits = 8, mode = 0 }) },
    ["precise"] = { quantized = quantize.resolve({ min = 0, max = 1, bits = 32, mode = 0 }) },
    ["nums"] = { array = "number" },
    ["tags"] = { map = "string" },
    ["child"] = QChild,
    ["items"] = { array = QChild },
    ["label"] = "string",
    ["_fields_by_index"] = { "yaw", "pitch", "precise", "nums", "tags", "child", "items", "label" },
})

return QState
