local Schema = require('colyseus.serialization.schema.schema')

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

function schema_serializer:set_state(encoded_state)
  self.state:decode(encoded_state)
end

function schema_serializer:patch(binary_patch)
  self.state:decode(binary_patch)
end

function schema_serializer:handshake(bytes)
  self.state = Schema.reflection_decode(bytes)
end

return schema_serializer

