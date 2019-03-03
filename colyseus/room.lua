local msgpack = require('colyseus.messagepack.MessagePack')

local Connection = require('colyseus.connection')
local protocol = require('colyseus.protocol')

local EventEmitter = require('colyseus.eventemitter')
local utils = require('colyseus.utils')
local decode = require('colyseus.serialization.schema.decode')
local storage = require('colyseus.storage')
local serialization = require('colyseus.serialization')

Room = {}
Room.__index = Room

function Room.create(name, options)
  local room = EventEmitter:new({
    serializer_id = nil,
    previous_code = nil
  })
  setmetatable(room, Room)
  room:init(name, options)
  return room
end

function Room:init(name, options)
  self.id = nil
  self.name = name
  self.options = options or {}
  self.connection = Connection.new()

  -- remove all listeners on leave
  self:on('leave', function()
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

function Room:has_joined ()
  return self.sessionId ~= nil
end

-- fossil-delta serializer only
function Room:listen (segments, callback, immediate)
  if self.serializer_id ~= "fossil-delta" then
    error(tostring(self.serializer_id) .. " serializer doesn't support .listen() method.")
    return
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
  if self.previous_code then
    self:on_message(binary_string)

  else
    self:on_message(utils.string_to_byte_array(binary_string))
  end
end

function Room:on_message (message)
  if self.previous_code == nil then
    local code = message[1]

    if (code == protocol.JOIN_ROOM) then
      local cursor = { offset = 2 }

      self.sessionId = decode.string(message, cursor)
      self.serializer_id = decode.string(message, cursor)

      local serializer = serialization.get_serializer(self.serializer_id)
      if not serializer then
        error("missing serializer: " .. self.serializer_id);
      end
      
      self.serializer = serializer.new()

      if self.serializer.handshake ~= nil then
        self.serializer.handshake(utils.table_slice(message, cursor.offset))
      end

      self:emit("join")

    elseif (code == protocol.JOIN_ERROR) then
      self:emit("error", message[2])

    elseif (code == protocol.LEAVE_ROOM) then
      self:leave()

    else 
      self.previous_code = code
    end

  else 
    if self.previous_code == protocol.ROOM_STATE then
      self:set_state(message)

    elseif self.previous_code == protocol.ROOM_STATE_PATCH then
      self:patch(message)

    elseif self.previous_code == protocol.ROOM_DATA then
      self:emit("message", msgpack.unpack(message))
    end

    self.previous_code = nil
  end
end

function Room:set_state (encoded_state)
  self.serializer:set_state(encoded_state)
  self:emit("statechange", state)
end

function Room:patch ( binary_patch )
  self.serializer:patch(binary_patch)
  self:emit("statechange", state)
end

function Room:leave()
  if self.connection.state == "OPEN" then
    self.connection:send({ protocol.LEAVE_ROOM })

  else
    self:emit("leave")
  end
end

function Room:send (data)
  self.connection:send({ protocol.ROOM_DATA, self.id, data })
end

return Room
