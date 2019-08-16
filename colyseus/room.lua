local msgpack = require('colyseus.messagepack.MessagePack')

local Connection = require('colyseus.connection')
local protocol = require('colyseus.protocol')

local EventEmitter = require('colyseus.eventemitter')
local utils = require('colyseus.utils')
local decode = require('colyseus.serialization.schema.schema')
local storage = require('colyseus.storage')
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
  room:init(name, options)
  return room
end

function Room:init(name)
  self.id = nil
  self.name = name
  self.connection = Connection.new()
  self.serializer = serialization.get_serializer('fossil-delta').new()

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
    self:on_batch_message(message)
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

function Room:on_batch_message(binary_string)
  local total_bytes = #binary_string
  local cursor = { offset = 1 }
  -- print("Room:on_batch_message, bytes =>", total_bytes)
  while cursor.offset <= total_bytes do
    -- print("Room:on_message (batch",total_bytes,"), offset =>", cursor.offset, ", byte on offset =>", string.byte(binary_string, cursor.offset))
    self:on_message(binary_string:sub(cursor.offset), cursor)
  end
end

function Room:on_message (binary_string, cursor)
  local it = { offset = 1 }

  if self.previous_code == nil then
    local message = utils.string_to_byte_array(binary_string)

    local code = message[it.offset]
    it.offset = it.offset + 1

    if code == protocol.JOIN_ROOM then
      self.serializer_id = decode.string(message, it)

      local serializer = serialization.get_serializer(self.serializer_id)
      if not serializer then
        error("missing serializer: " .. self.serializer_id);
      end

      if self.serializer_id ~= "fossil-delta" then
        self.serializer = serializer.new()
      end

      if #message > it.offset and self.serializer.handshake ~= nil then
        self.serializer:handshake(message, it)
      end

      self:emit("join")

    elseif code == protocol.JOIN_ERROR then
      local err = decode.string(message, it)
      self:emit("error", err)

    elseif code == protocol.LEAVE_ROOM then
      self:leave()

    else
      self.previous_code = code
    end

  else
    -- print("PREVIOUS CODE", self.previous_code)

    if self.previous_code == protocol.ROOM_STATE then
      self:set_state(binary_string, it)

    elseif self.previous_code == protocol.ROOM_STATE_PATCH then
      self:patch(binary_string, it)

    elseif self.previous_code == protocol.ROOM_DATA then
      local msgpack_cursor = {
          s = binary_string,
          i = 1,
          j = #binary_string,
          underflow = function() error "missing bytes" end,
      }
      local data = msgpack.unpack_cursor(msgpack_cursor)
      it.offset = msgpack_cursor.i

      self:emit("message", data)
    end

    self.previous_code = nil
  end

  cursor.offset = cursor.offset + it.offset - 1
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
      self.connection:send({ protocol.LEAVE_ROOM })
    else
      self.connection:close()
    end
  else
    self:emit("leave")
  end
end

function Room:send (data)
  self.connection:send({ protocol.ROOM_DATA, data })
end

return Room
