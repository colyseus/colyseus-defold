local Connection = require('colyseus.connection')
local Room = require('colyseus.room')
local protocol = require('colyseus.protocol')
local EventEmitter = require('colyseus.eventemitter')
local msgpack = require('colyseus.messagepack.MessagePack')
local storage = require('colyseus.storage')

local client = { VERSION = "0.8.0" }
client.__index = client

function client.new (endpoint)
  local instance = EventEmitter:new({
    id = storage.get_item("colyseusid"),
    roomStates = {}, -- table
    rooms = {}, -- table
    connectingRooms = {}, -- table
    roomsAvailableRequests = {}, -- table
    requestId = 0, -- number
  })
  setmetatable(instance, client)
  instance:init(endpoint)
  return instance
end

function client:init(endpoint)
  self.hostname = endpoint

  -- ensure the ends with "/", to concat with path during create_connection.
  if string.sub(self.hostname, -1) ~= "/" then
    self.hostname = self.hostname .. "/"
  end

  self.connection = Connection.new()

  self.connection:on("open", function()
    if storage.get_item("colyseusid") ~= nil then
      self:emit("open")
    end
  end)

  self.connection:on("message", function(message)
    self:on_batch_message(message)
  end)

  self.connection:on("close", function(message)
    self:emit("close", message)
  end)

  self.connection:on("error", function(message)
    self:emit("error", message)
  end)

  self.connection:open(self:_build_endpoint())
end

function client:get_available_rooms(roomName, callback)
  local requestId = self.requestId + 1
  self.connection:send({ protocol.ROOM_LIST, requestId, roomName })

  -- TODO: add timeout to cancel request.

  self.roomsAvailableRequests[requestId] = function(rooms)
    self.roomsAvailableRequests[requestId] = nil
    callback(rooms)
  end

  self.requestId = requestId
end

function client:_build_endpoint(path, options)
  path = path or ""
  options = options or {}

  local params = { "colyseusid=" .. storage.get_item("colyseusid") }
  for k, v in pairs(options) do
    table.insert(params, k .. "=" .. tostring(v))
  end
  
  return self.hostname .. path .. "?" .. table.concat(params, "&")
end

function client:loop(timeout)
  self.connection:loop(timeout)

  for k, room in pairs(self.rooms) do
    room:loop(timeout)
  end
end

function client:close()
  self.connection:close()
end

function client:join(...)
  local args = {...}

  local roomName = args[1]
  local options = args[2] or {}

  self.requestId = self.requestId + 1
  options.requestId = self.requestId;

  local room = Room.create(roomName, options)

  -- remove references on leaving
  room:on("leave", function()
    self.rooms[room.id] = nil
    self.connectingRooms[options.requestId] = nil
  end)

  self.connectingRooms[options.requestId] = room

  self.connection:send({ protocol.JOIN_ROOM, roomName, options })

  return room
end

function client:rejoin(roomName, sessionId)
  -- reopen client connection if it's closed
  -- if self.connection.state == "CLOSED" then
  --  self.connection:open()
  --end

  return self:join(roomName, {
    sessionId = sessionId
  })
end

function client:on_batch_message(messages)
  for _, message in msgpack.unpacker(messages) do
    self:on_message(message)
  end
end

function client:on_message(message)
  if type(message[1]) == "number" then
    local roomId = message[2]

    if message[1] == protocol.USER_ID then
      self.id = message[2]
      storage.set_item("colyseusid", self.id)

      self:emit('open')

    elseif (message[1] == protocol.JOIN_ROOM) then
      local requestId = message[3]
      local room = self.connectingRooms[requestId]

      if not room then
        print("colyseus.client: client left room before receiving session id.")
        return
      end

      room.id = roomId
      room:connect( self:_build_endpoint(room.id, room.options) )

      self.rooms[room.id] = room
      self.connectingRooms[ requestId ] = nil;

    elseif (message[1] == protocol.JOIN_ERROR) then
      self:emit("error", message[3])
      self.rooms[roomId] = nil

    elseif (message[1] == protocol.ROOM_LIST) then
      if self.roomsAvailableRequests[self.requestId] ~= nil then
        self.roomsAvailableRequests[message[2]](message[3])
      end

    else
      self:emit('message', message)

    end
  end
end

return client
