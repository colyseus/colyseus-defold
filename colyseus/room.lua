local msgpack = require('colyseus.messagepack.MessagePack')
local fossil_delta = require('colyseus.fossil_delta.fossil_delta')

local protocol = require('colyseus.protocol')
local DeltaContainer = require('colyseus.delta_listener.delta_container')

local utils = require('colyseus.utils')

Room = {}
Room.__index = Room

function Room.create(name)
  local room = DeltaContainer.new()
  setmetatable(room, Room)
  room:init(name)
  return room
end

-- inherits from DeltaContainer
setmetatable(Room, { __index = DeltaContainer })

function Room:init(name, options)
  self.id = nil
  self.name = name
  self.options = options or {}

  -- remove all listeners on leave
  self:on('leave', self.off)
end

function Room:connect (connection)
  self.connection = connection

  self.connection:on("message", function(message)
    self:on_batch_message(message)
  end)

  self.connection:on("close", function(e)
     -- TODO: check for handshake errors to emit "error" event?
    self:emit("leave", e)
  end)
end

function Room:loop ()
  if self.connection ~= nil then
    self.connection:loop()
  end
end

function Room:on_batch_message (messages)
  for _, message in msgpack.unpacker(messages) do
    self:on_message(message)
  end
end

function Room:on_message (message)
  local code = message[1]

  if (code == protocol.JOIN_ROOM) then
    self.sessionId = message[2]
    self:emit("join")

  elseif (code == protocol.JOIN_ERROR) then
    self:emit("error", message[2])

  elseif (code == protocol.ROOM_STATE) then
    local state = message[2]
    -- local remoteCurrentTime = message[3]
    -- local remoteElapsedTime = message[4]

    self:setState( state, remoteCurrentTime, remoteElapsedTime )

  elseif (code == protocol.ROOM_STATE_PATCH) then
    self:patch(message[2])

  elseif (code == protocol.ROOM_DATA) then
    self:emit("data", message[2])

  elseif (code == protocol.LEAVE_ROOM) then
    self:leave()
  end

end

function Room:setState (encodedState, remoteCurrentTime, remoteElapsedTime)
  local state = msgpack.unpack(encodedState)

  self:set(state)
  self._previousState = utils.string_to_byte_array(encodedState)

  self:emit("update", state)
end

function Room:patch ( binaryPatch )
  -- apply patch
  self._previousState = fossil_delta.apply(self._previousState, binaryPatch)

  local data = msgpack.unpack( utils.byte_array_to_string(self._previousState) )

  -- trigger state callbacks
  self:set( data )

  self:emit("update", self.data)
end

function Room:leave()
  if (self.connection) then
    self.connection:close()

  else
    self:emit("leave")
  end
end

function Room:send (data)
  self.connection:send({ protocol.ROOM_DATA, self.id, data })
end

return Room
