local msgpack = require('colyseus.messagepack.MessagePack')

local Connection = require('colyseus.connection')
local protocol = require('colyseus.protocol')

local EventEmitter = require('colyseus.eventemitter')
local utils = require('colyseus.utils.utils')
local decode = require('colyseus.serializer.schema.encoding.decode')
local encode = require('colyseus.serializer.schema.encoding.encode')
local serialization = require('colyseus.serialization')

---@class Room : EventEmitterInstance
---@field state table
---@field session_id string
---@field room_id string
---@field connection Connection
Room = {}
Room.__index = function (self, key)
  if key == "state" then
    -- state getter
    return self.serializer:get_state()
  else
    return Room[key]
  end
end

---@private
---@param name string
---@return Room
function Room.new(name)
  local room = EventEmitter:new({
    serializer_id = nil,
    reconnection_token = nil,
    previous_code = nil
  })
  setmetatable(room, Room)
  room:init(name)
  return room
end

---@private
---@param name string
function Room:init(name)
  self.name = name
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

---@private
---@param endpoint string
---@param dev_mode_close_callback nil|function
---@param room nil|Room
function Room:connect (endpoint, dev_mode_close_callback, room)
  if room == nil then room = self end

  room.connection = Connection.new()

  room.connection:on("message", function(message)
    room:_on_message(message, { offset = 1 })
  end)

  room.connection:on("close", function(e)
    if dev_mode_close_callback ~= nil and e.code == protocol.WS_CLOSE_CODE.DEVMODE_RESTART then
      dev_mode_close_callback()
    else
      room:emit("leave", e)
    end
  end)

  room.connection:on("error", function(e)
    room:emit("error", e)
  end)

  room.connection:open(endpoint)
end

---@param type string
---@param handler fun(message:table)
function Room:on_message(type, handler)
  local _self = self

  local message_type = self:get_message_handler_key(type)
  self.on_message_handlers[message_type] = handler

  return function()
    _self.on_message_handlers[message_type] = nil
  end
end

---@private
function Room:_on_batch_message(binary_string)
  local total_bytes = #binary_string
  local cursor = { offset = 1 }
  while cursor.offset <= total_bytes do
    self:_on_message(binary_string, cursor)
  end
end

---@private
function Room:_on_message (binary_string, it)
  local message = utils.string_to_byte_array(binary_string)

  local code = message[it.offset]
  it.offset = it.offset + 1

  if code == protocol.JOIN_ROOM then
    local reconnection_token = decode.string(message, it)
    self.serializer_id = decode.string(message, it)

    local serializer = serialization.get_serializer(self.serializer_id)
    if not serializer then error("missing serializer: " .. self.serializer_id); end

    self.reconnection_token = {
      room_id = self.room_id,
      reconnection_token = reconnection_token,
    }

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

  elseif code == protocol.ROOM_DATA_BYTES then
    local message_type

    if decode.string_check(message, it) then
      message_type = decode.string(message, it)
    else
      message_type = decode.number(message, it)
    end

    local byte_array = {}
    for i = it.offset, #binary_string, 1 do
      byte_array[#byte_array+1] = message[i]
    end

    self:_dispatch_message(message_type, byte_array)
  end
end

---@private
function Room:set_state (encoded_state, it)
  self.serializer:set_state(encoded_state, it)
  self:emit("statechange", self.serializer:get_state())
end

---@private
function Room:patch (binary_patch, it)
  self.serializer:patch(binary_patch, it)
  self:emit("statechange", self.serializer:get_state())
end

---@param consented nil|boolean
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

---@param message_type number|string
---@param message table|boolean|number|string
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

---@param message_type string
---@param bytes table
function Room:send_bytes (message_type, bytes)
  local initial_bytes = { protocol.ROOM_DATA }
  local mtype = type(message_type)

  if mtype == "string" then
      encode.string(initial_bytes, message_type);

  elseif mtype == "number" then
      encode.number(initial_bytes, message_type);
  else
    error("Protocol.ROOM_DATA_BYTES: message type not supported '" .. tostring(type) .. "'")
  end

  self.connection:send(utils.byte_array_to_string(initial_bytes) .. utils.byte_array_to_string(bytes));
end

---@private
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

---@private
function Room:get_message_handler_key(message_type)
  local t = type(message_type)

  if t == "string" then
    return "s" .. message_type
  elseif t == "number" then
    return "i" .. tostring(message_type)
  else
    error("invalid message type.")
  end
end

return Room
