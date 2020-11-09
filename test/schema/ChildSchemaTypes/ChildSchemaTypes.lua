-- 
-- THIS FILE HAS BEEN GENERATED AUTOMATICALLY
-- DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
-- 
-- GENERATED USING @colyseus/schema 1.0.0-alpha.58
-- 

local schema = require 'colyseus.serialization.schema.schema'
local IAmAChild = require 'test.schema.ChildSchemaTypes.IAmAChild'

local ChildSchemaTypes = schema.define({
    ["child"] = IAmAChild,
    ["secondChild"] = IAmAChild,
    ["_fields_by_index"] = { "child", "secondChild" },
})

return ChildSchemaTypes
