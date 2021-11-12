local Connection = require('colyseus.connection')
local Room = require('colyseus.room')
local protocol = require('colyseus.protocol')
local EventEmitter = require('colyseus.eventemitter')
local storage = require('colyseus.storage')

local utils = require('colyseus.utils.utils')
local URL = require('colyseus.utils.url')
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

function client:init(endpoint_or_settings)
  if type(endpoint_or_settings) == "string" then
    local parsed_url = URL.parse(endpoint_or_settings)
    self.settings = {}
    self.settings.hostname = parsed_url.host
    self.settings.port = parsed_url.port
    self.settings.use_ssl = (parsed_url.scheme == "wss")

  else
    self.settings = endpoint_or_settings
  end

  -- ensure hostname does not end with "/"
  if string.sub(self.settings.hostname, -1) == "/" then
    self.settings.hostname = self.settings.hostname:sub(0, -2)
  end
end

function client:get_available_rooms(room_name, callback)
  local url = self:_build_http_endpoint("/matchmake/" .. room_name)
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

  local headers = {
    ['Accept'] = 'application/json',
    ['Content-Type'] = 'application/json'
  }

  local url = self:_build_http_endpoint("/matchmake/" .. method .. "/" .. room_name)

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

  room:connect(self:_build_ws_endpoint(response.room, { sessionId = room.sessionId }))
end

function client:_build_ws_endpoint(room, options)
  options = options or {}

  local params = {}
  for k, v in pairs(options) do
    table.insert(params, k .. "=" .. tostring(v))
  end

  -- build request endpoint
  local protocol = (self.settings.use_ssl and "wss") or "ws"
  local port = ((self.settings.port ~= 80 and self.settings.port ~= 443) and ":" .. self.settings.port) or ""
  local public_address = (room.publicAddress) or self.settings.hostname .. port

  return protocol .. "://" .. public_address .. "/" .. room.processId .. "/" .. room.roomId .. "?" .. table.concat(params, "&")
end

function client:_build_http_endpoint(path, query_params)
  query_params = query_params or {}

  local params = {}
  for k, v in pairs(query_params) do
    table.insert(params, k .. "=" .. tostring(v))
  end

  -- build request endpoint
  local protocol = (self.settings.use_ssl and "https") or "http"
  local port = ((self.settings.port ~= 80 and self.settings.port ~= 443) and ":" .. self.settings.port) or ""
  local public_address = self.settings.hostname .. port
  -- local public_address = (room.publicAddress) or self.settings.hostname .. port

  return protocol .. "://" .. public_address .. path .. "?" .. table.concat(params, "&")
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
