local EventEmitter = require('colyseus.events').EventEmitter
local protocol = require('colyseus.protocol')
local msgpack = require('colyseus.messagepack.MessagePack')
local fossil_delta = require('colyseus.fossil_delta.fossil_delta')

Room = {}
Room.__index = Room

function Room.create(name)
  local room = EventEmitter:new({
    id = nil,
    state = {}
  })
  setmetatable(room, Room)
  room:init(name)
  return room
end

function Room:init(name)
  self.name = name

  -- remove all listeners on leave
  self:on('leave', self.off)
end

function Room:connect (connection)
  self.connection = connection
  self.connection:on("message", self.on_message)
  self.connection:on("close", function(e)
    self:emit("leave", e)
  end)
end

function Room:on_message (message)
  local message = msgpack.unpack( message )
  local code = message[1];

  if (code == protocol.JOIN_ROOM) then
    self.sessionId = message[2]
    self:emit("join")

  elseif (code == protocol.JOIN_ERROR) then
    self:emit("error", message[3])

  elseif (code == protocol.ROOM_STATE) then
    local state = message[3]
    local remoteCurrentTime = message[4]
    local remoteElapsedTime = message[5]

    self:setState( state, remoteCurrentTime, remoteElapsedTime )

  elseif (code == protocol.ROOM_STATE_PATCH) then
    self:patch(message[3])

  elseif (code == protocol.ROOM_DATA) then
    self:emit("data", message[3])

  elseif (code == protocol.LEAVE_ROOM) then
    self:leave()
  end

end

function Colyseus:setState (encodedState, remoteCurrentTime, remoteElapsedTime)
  local state = msgpack.unpack(encodedState)

  self:set(state)
  self._previousState = encodedState

  this:emit("update", state)
end

function Colyseus:patch ( binaryPatch )
  -- apply patch
  this._previousState = fossil_delta.apply( this._previousState, binaryPatch);

  -- trigger state callbacks
  this:set( msgpack.unpack( this._previousState ) );

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
