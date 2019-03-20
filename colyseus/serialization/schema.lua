local Schema = require('colyseus.serialization.schema.schema')
local utils = require('colyseus.utils')

local schema_serializer = {}
schema_serializer.__index = schema_serializer

function schema_serializer.new ()
  local instance = {
    state = nil
  }
  setmetatable(instance, schema_serializer)
  return instance
end

function schema_serializer:get_state()
  return self.state
end

function schema_serializer:set_state(encoded_state, it)
  -- print("schema_serializer:set_state")

  self.state:decode(utils.string_to_byte_array(encoded_state), it)
end

function schema_serializer:patch(binary_patch, it)
  -- print("schema_serializer:patch")

  self.state:decode(utils.string_to_byte_array(binary_patch), it)
end

function schema_serializer:handshake(bytes, it)
  -- print("schema_serializer:handshake")

  self.state = Schema.reflection_decode(bytes, it)
end

return schema_serializer

