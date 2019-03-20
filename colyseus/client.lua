local Connection = require('colyseus.connection')
local Room = require('colyseus.room')
local protocol = require('colyseus.protocol')
local EventEmitter = require('colyseus.eventemitter')
local storage = require('colyseus.storage')

local utils = require('colyseus.utils')
local decode = require('colyseus.serialization.schema.schema')
local msgpack = require('colyseus.messagepack.MessagePack')

local client = {}
client.__index = client

function client.new (endpoint, connect_on_init)
  local instance = EventEmitter:new({
    id = storage.get_item("colyseusid"), -- client id
    rooms = {}, -- table
    connecting_rooms = {}, -- table
    rooms_available_request = {}, -- table
    requestId = 0, -- number
  })
  setmetatable(instance, client)
  instance:init(endpoint, connect_on_init)
  return instance
end

function client:init(endpoint, connect_on_init)
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
    print("CONNECTION ERROR!")
    self:emit("error", message)
  end)

  if connect_on_init or connect_on_init == nil then
    self:connect()
  end
end

function client:connect()
  self.connection:open(self:_build_endpoint())
end

function client:get_available_rooms(room_name, callback)
  local requestId = self.requestId + 1
  self.connection:send({ protocol.ROOM_LIST, requestId, room_name })

  -- TODO: add timeout to cancel request.

  self.rooms_available_request[requestId] = function(rooms)
    self.rooms_available_request[requestId] = nil
    callback(rooms)
  end

  self.requestId = requestId
end

function client:_build_endpoint(path, options)
  path = path or ""
  options = options or {}

  local params = { "colyseusid=" .. (self.id or "") }
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

function client:join(room_name, options)
  return self:create_room_request(room_name, options or {})
end

function client:rejoin(room_name, sessionId)
  return self:join(room_name, {
    sessionId = sessionId
  })
end

function client:create_room_request(room_name, options, reuse_room_instance, retry_count)
  self.requestId = self.requestId + 1
  options.requestId = self.requestId;

  local room = reuse_room_instance or Room.create(room_name, options)

  local on_room_leave = function()
    room:off("error", on_room_leave)

    if room.id then
      self.rooms[room.id] = nil
    end

    self.connecting_rooms[options.requestId] = nil
  end

  local on_room_error = function()
    room:off("error", on_room_error)
    if not room:has_joined() then
      on_room_leave()

      retry_count = (retry_count or 0) + 1
      if options['retry_times'] and retry_count <= options['retry_times'] then
        self:create_room_request(room_name, options, room, retry_count)
      end
    end
  end

  -- remove references on leaving
  room:on("leave", on_room_leave)
  room:on("error", on_room_error)

  self.connecting_rooms[options.requestId] = room

  self.connection:send({ protocol.JOIN_REQUEST, room_name, options })

  return room
end

function client:on_batch_message(binary_string)
  local total_bytes = #binary_string

  local cursor = { offset = 1 }
  while cursor.offset <= total_bytes do
    self:on_message(binary_string:sub(cursor.offset), cursor)
  end
end

function client:on_message(binary_string, cursor)
  local it = { offset = 1 }

  if self.previous_code == nil then
    local message = utils.string_to_byte_array(binary_string)

    local code = message[it.offset]
    it.offset = it.offset + 1

    if code == protocol.USER_ID then
      self.id = decode.string(message, it)

      storage.set_item("colyseusid", self.id)

      self:emit('open')

    elseif code == protocol.JOIN_REQUEST then
      local requestId = message[it.offset]
      it.offset = it.offset + 1

      local room_id = decode.string(message, it)
      local room = self.connecting_rooms[requestId]

      if not room then
        print("colyseus.client: client left room before receiving session id.")
        return
      end

      room.id = room_id
      room:connect( self:_build_endpoint(room.id, room.options) )

      self.rooms[room.id] = room
      self.connecting_rooms[requestId] = nil;

    elseif code == protocol.JOIN_ERROR then
      local err = decode.string(message, it)
      print("JOIN_ERROR!")
      self:emit("error", err)

    elseif code == protocol.ROOM_LIST then
      self.previous_code = message[1]

    end

  else
    if self.previous_code == protocol.ROOM_LIST then
      local msgpack_cursor = {
          s = binary_string,
          i = 1,
          j = #binary_string,
          underflow = function() error "missing bytes" end,
      }
      local room_list = msgpack.unpack_cursor(msgpack_cursor)
      it.offset = msgpack_cursor.i

      local request_id = room_list[1]
      local rooms = room_list[2]

      if self.rooms_available_request[request_id] ~= nil then
        self.rooms_available_request[request_id](rooms)
      end
    end

    self.previous_code = nil
  end

  cursor.offset = cursor.offset + it.offset - 1
end

return client
