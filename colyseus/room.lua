local msgpack = require('colyseus.messagepack.MessagePack')

local Connection = require('colyseus.connection')
local protocol = require('colyseus.protocol')

local EventEmitter = require('colyseus.eventemitter')
local utils = require('colyseus.utils')
local decode = require('colyseus.serialization.schema.schema').decode
local encode = require('colyseus.serialization.schema.encode')
local serialization = require('colyseus.serialization')

Room = {}
Room.__index = function (self, key)
  if key == "state" then
    -- state getter
    return self.serializer:get_state()
  else
    return Room[key]
  end
end

function Room.new(name)
  local room = EventEmitter:new({
    serializer_id = nil,
    previous_code = nil
  })
  setmetatable(room, Room)
  room:init(name)
  return room
end

function Room:init(name)
  self.id = nil
  self.name = name
  self.connection = Connection.new()
  self.serializer = nil
  self.on_message_handlers = {}

  -- remove all listeners on leave
  self:on('leave', function()
    if self.serializer and self.serializer.teardown ~= nil then
      self.serializer:teardown();
    end

    self:off()
  end)
end

function Room:connect (endpoint)
  self.connection:on("message", function(message)
    self:_on_batch_message(message)
  end)

  self.connection:on("close", function(e)
     -- TODO: check for handshake errors to emit "error" event?
    self:emit("leave", e)
  end)

  self.connection:on("error", function(e)
    self:emit("error", e)
  end)

  self.connection:open(endpoint)
end

-- fossil-delta serializer only
function Room:listen (segments, callback, immediate)
  if self.serializer_id ~= "fossil-delta" then
    error(tostring(self.serializer_id) .. " serializer doesn't support .listen() method.")
    return
  end
  if self.serializer_id == nil then
    print("DEPRECATION WARNING: room:listen() should be called after join has been successful")
  end
  return self.serializer.state:listen(segments, callback, immediate)
end

-- fossil-delta serializer only
function Room:remove_listener (listener)
  return self.serializer.state:remove_listener(listener)
end

function Room:loop (timeout)
  if self.connection ~= nil then
    self.connection:loop(timeout)
  end
end

function Room:on_message(type, handler)
  local _self = self

  local message_type = self:get_message_handler_key(type)
  self.on_message_handlers[message_type] = handler

  return function()
    _self.on_message_handlers[message_type] = nil
  end
end

function Room:_on_batch_message(binary_string)
  local total_bytes = #binary_string
  local cursor = { offset = 1 }
  -- print("Room:_on_batch_message, total_bytes =>", total_bytes)
  while cursor.offset <= total_bytes do
    -- print("Room:_on_message (total_bytes:",total_bytes,"), offset =>", cursor.offset, ", byte on offset =>", string.byte(binary_string, cursor.offset))
    self:_on_message(binary_string, cursor)
  end
end

function Room:_on_message (binary_string, it)
  -- local it = { offset = 1 }
  local message = utils.string_to_byte_array(binary_string)

  local code = message[it.offset]
  it.offset = it.offset + 1

  if code == protocol.JOIN_ROOM then
    self.serializer_id = decode.string(message, it)

    local serializer = serialization.get_serializer(self.serializer_id)
    if not serializer then error("missing serializer: " .. self.serializer_id); end

    self.serializer = serializer:new()

    if #message > it.offset and self.serializer.handshake ~= nil then
      self.serializer:handshake(message, it)
    end

    self:emit("join")

    -- acknowledge JOIN_ROOM
    self.connection:send(utils.byte_array_to_string({ protocol.JOIN_ROOM, 0 })) -- 0 is necessary for HTML5 builds (null-terminated string)

  elseif code == protocol.ERROR then
    local code = decode.number(message, it)
    local error = decode.string(message, it)
    self:emit("error", { code = code, error = error })

  elseif code == protocol.LEAVE_ROOM then
    self:leave()

  elseif code == protocol.ROOM_STATE then
    self:set_state(message, it)

  elseif code == protocol.ROOM_STATE_PATCH then
    self:patch(message, it)

  elseif code == protocol.ROOM_DATA_SCHEMA then
    local typeid = decode.number(message, it)

    local context = self.serializer:get_state()._context
    local message_type = context:get(typeid)
    local schema_message = message_type:new()

    it.offset = it.offset + 1
    schema_message:decode(message, it)

    self:_dispatch_message(message_type, schema_message)

  elseif code == protocol.ROOM_DATA then
    local message_type

    if decode.string_check(message, it) then
      message_type = decode.string(message, it)
    else
      message_type = decode.number(message, it)
    end

    local message = nil

    if #binary_string > it.offset then
      local msgpack_cursor = {
          s = binary_string,
          i = it.offset,
          j = #binary_string,
          underflow = function() error "missing bytes" end,
      }
      message = msgpack.unpack_cursor(msgpack_cursor)
      it.offset = msgpack_cursor.i
    end

    self:_dispatch_message(message_type, message)
  end

  -- cursor.offset = cursor.offset + it.offset - 1
end

function Room:set_state (encoded_state, it)
  self.serializer:set_state(encoded_state, it)
  self:emit("statechange", self.serializer:get_state())
end

function Room:patch (binary_patch, it)
  self.serializer:patch(binary_patch, it)
  self:emit("statechange", self.serializer:get_state())
end

function Room:leave(consented)
  if self.connection.state == "OPEN" then
    if consented or consented == nil then
      self.connection:send(utils.byte_array_to_string({ protocol.LEAVE_ROOM, 0 }))
    else
      self.connection:close()
    end
  else
    self:emit("leave")
  end
end

function Room:send (message_type, message)
  local initial_bytes = { protocol.ROOM_DATA }
  local mtype = type(message_type)

  if mtype == "string" then
      encode.string(initial_bytes, message_type);

  elseif mtype == "number" then
      encode.number(initial_bytes, message_type);
  else
    error("Protocol.ROOM_DATA: message type not supported '" .. tostring(type) .. "'")
  end

  local encoded

  if message ~= nil then
    encoded = msgpack.pack(message)
  else
    encoded = ''
  end

  self.connection:send(utils.byte_array_to_string(initial_bytes) .. encoded);
end

function Room:_dispatch_message (message_type, message)
  local type_key = self:get_message_handler_key(message_type);

  if self.on_message_handlers[type_key] then
    self.on_message_handlers[type_key](message);

  elseif self.on_message_handlers['*'] then
    self.on_message_handlers['*'](message_type, message)

  else
    print('on_message not registered for type "' .. tostring(message_type) .. '".')
  end
end

function Room:get_message_handler_key(message_type)
  local t = type(message_type)

  if t == "table" then
    return "s" .. tostring(message_type._typeid)
  elseif t == "string" then
    return message_type
  elseif t == "number" then
    return "i" .. tostring(message_type)
  else
    error("invalid message type.")
  end
end

return Room
