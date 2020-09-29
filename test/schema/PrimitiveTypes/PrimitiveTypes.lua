-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 1.0.0-alpha.58
-- 

local schema = require 'colyseus.serialization.schema.schema'


local PrimitiveTypes = schema.define({
    ["int8"] = "int8",
    ["uint8"] = "uint8",
    ["int16"] = "int16",
    ["uint16"] = "uint16",
    ["int32"] = "int32",
    ["uint32"] = "uint32",
    ["int64"] = "int64",
    ["uint64"] = "uint64",
    ["float32"] = "float32",
    ["float64"] = "float64",
    ["varint_int8"] = "number",
    ["varint_uint8"] = "number",
    ["varint_int16"] = "number",
    ["varint_uint16"] = "number",
    ["varint_int32"] = "number",
    ["varint_uint32"] = "number",
    ["varint_int64"] = "number",
    ["varint_uint64"] = "number",
    ["varint_float32"] = "number",
    ["varint_float64"] = "number",
    ["str"] = "string",
    ["boolean"] = "boolean",
    ["_fields_by_index"] = { "int8", "uint8", "int16", "uint16", "int32", "uint32", "int64", "uint64", "float32", "float64", "varint_int8", "varint_uint8", "varint_int16", "varint_uint16", "varint_int32", "varint_uint32", "varint_int64", "varint_uint64", "varint_float32", "varint_float64", "str", "boolean" },
})

return PrimitiveTypes
