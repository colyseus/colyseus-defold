local Connection = require('colyseus.connection')
local Auth = require('colyseus.auth')
local Room = require('colyseus.room')
local Push = require('colyseus.push')
local protocol = require('colyseus.protocol')
local EventEmitter = require('colyseus.eventemitter')
local storage = require('colyseus.storage')

local utils = require('colyseus.utils')
local decode = require('colyseus.serialization.schema.schema')
local JSON = require('colyseus.serialization.json')
local msgpack = require('colyseus.messagepack.MessagePack')

local client = {}
client.__index = client

function client.new (endpoint)
  local instance = EventEmitter:new()
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

  self.auth = Auth.new(endpoint)
  self.push = Push.new(endpoint)

  self.rooms = {}
end

function client:get_available_rooms(room_name, callback)
  local url = "http" .. self.hostname:sub(3) .. "matchmake/" .. room_name
  local headers = { ['Accept'] = 'application/json' }
  self:_request(url, 'GET', headers, nil, callback)
end

function client:join_or_create(room_name, options, callback)
  return self:create_matchmake_request('joinOrCreate', room_name, options or {}, callback)
end

function client:create(room_name, options, callback)
  return self:create_matchmake_request('create', room_name, options or {}, callback)
end

function client:join(room_name, options, callback)
  return self:create_matchmake_request('join', room_name, options or {}, callback)
end

function client:join_by_id(room_id, options, callback)
  return self:create_matchmake_request('joinById', room_id, options or {}, callback)
end

function client:reconnect(room_id, session_id, callback)
  return self:create_matchmake_request('joinById', room_id, { sessionId = session_id }, callback)
end

function client:create_matchmake_request(method, room_name, options, callback)
  if type(options) == "function" then
    callback = options
    options = {}
  end

  if self.auth:has_token() then
    options.token = self.auth.token
  end

  local headers = {
    ['Accept'] = 'application/json',
    ['Content-Type'] = 'application/json'
  }

  local url = "http" .. self.hostname:sub(3) .. "matchmake/" .. method .. "/" .. room_name
  self:_request(url, 'POST', headers, JSON.encode(options), function(err, response)
    if (err) then return callback(err) end

    self:consume_seat_reservation(response, callback)
  end)
end

function client:consume_seat_reservation(response, callback)
  local room = Room.new(response.room.name)
  room.id = response.room.roomId
  room.sessionId = response.sessionId

  local on_error = function(err)
    callback(err, nil)
    room:off()
  end

  local on_join = function()
    room:off('error', on_error)
    callback(nil, room)
  end

  room:on('error', on_error)
  room:on('join', on_join)
  room:on('leave', function()
    self.rooms[room.id] = nil
  end)
  self.rooms[room.id] = room

  room:connect(self:_build_endpoint(response.room.processId .. "/" .. room.id, {sessionId = room.sessionId}))
end

function client:_build_endpoint(path, options)
  path = path or ""
  options = options or {}

  local params = {}
  for k, v in pairs(options) do
    table.insert(params, k .. "=" .. tostring(v))
  end

  return self.hostname .. path .. "?" .. table.concat(params, "&")
end

function client:_request(url, method, headers, body, callback)
  http.request(url, method, function(self, id, response)
		local data = response.response ~= '' and json.decode(response.response)
    local has_error = (response.status >= 400)
    local err = nil

    if not data and response.status == 0 then
      return callback("offline")
    end

    if has_error or data.error then
      err = (not data or next(data) == nil) and response.response or data.error
    end

    callback(err, data)
	end, headers, body or "", { timeout = Connection.config.connect_timeout })
end

return client
