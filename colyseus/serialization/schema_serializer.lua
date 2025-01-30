local reflection = require('colyseus.serialization.schema.reflection')
local reference_tracker = require('colyseus.serialization.schema.reference_tracker')
local Decoder = require('colyseus.serialization.schema.decoder')

---@class schema_serializer
---@field decoder Decoder
local schema_serializer = {}

function schema_serializer:new ()
  local instance = { decoder = nil, }
  setmetatable(instance, self)
  self.__index = self
  return instance
end

function schema_serializer:get_state()
  return self.decoder.state
end

function schema_serializer:set_state(encoded_state, it)
  self.decoder:decode(encoded_state, it)
end

function schema_serializer:patch(binary_patch, it)
  self.decoder:decode(binary_patch, it)
end

function schema_serializer:teardown()
  self.decoder.refs:clear()
end

function schema_serializer:handshake(bytes, it)
  self.decoder = reflection.decode(bytes, it)
end

return schema_serializer
