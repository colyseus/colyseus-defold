--
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
--
-- GENERATED USING @colyseus/schema 3.0.0-alpha.45
--

local schema = require 'colyseus.serializer.schema.schema'


---@class Vec3: Schema
---@field x number
---@field y number
---@field z number
local Vec3 = schema.define({
    ["x"] = "number",
    ["y"] = "number",
    ["z"] = "number",
    ["_fields_by_index"] = { "x", "y", "z" },
})

return Vec3
