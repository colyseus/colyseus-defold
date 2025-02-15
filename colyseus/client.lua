local Room = require('colyseus.room')
local Auth = require('colyseus.auth')
local HTTP = require('colyseus.http')

local EventEmitter = require('colyseus.eventemitter')
local URL = require('colyseus.utils.url')

local info = sys.get_sys_info()

---@class Client : EventEmitterInstance
---@field auth Auth
---@field http HTTP
local Client = {}
Client.__index = Client

---@private
function Client:init(endpoint_or_settings)
  if type(endpoint_or_settings) == "string" then
    local parsed_url = URL.parse(endpoint_or_settings)
    self.settings = {}
    self.settings.hostname = parsed_url.host
    self.settings.port = parsed_url.port
      or ((parsed_url.scheme == "wss" or parsed_url.scheme == "https") and 443)
      or ((parsed_url.scheme == "ws" or parsed_url.scheme == "http") and 80)
    self.settings.use_ssl = (parsed_url.scheme == "wss" or parsed_url.scheme == "https")

    -- force SSL on HTML5 if running on HTTPS protocol
    if info.system_name == "HTML5" then
      self.settings.use_ssl = html5.run("window['location']['protocol']") == "https:"
    end

  else
    self.settings = endpoint_or_settings
  end

  -- ensure hostname does not end with "/"
  if string.sub(self.settings.hostname, -1) == "/" then
    self.settings.hostname = self.settings.hostname:sub(0, -2)
  end

  self.http = HTTP.new(self)
  self.auth = Auth.new(self)
end

---@param room_name string
---@param options_or_callback nil|table|fun(err:table, room:Room)
---@param callback nil|fun(err:table, room:Room)
function Client:join_or_create(room_name, options_or_callback, callback)
  return self:create_matchmake_request('joinOrCreate', room_name, options_or_callback or {}, callback)
end

---@param room_name string
---@param options_or_callback nil|table|fun(err:table, room:Room)
---@param callback nil|fun(err:table, room:Room)
function Client:create(room_name, options_or_callback, callback)
  return self:create_matchmake_request('create', room_name, options_or_callback or {}, callback)
end

---@param room_name string
---@param options_or_callback nil|table|fun(err:table, room:Room)
---@param callback nil|fun(err:table, room:Room)
function Client:join(room_name, options_or_callback, callback)
  return self:create_matchmake_request('join', room_name, options_or_callback or {}, callback)
end

---@param room_id string
---@param options_or_callback nil|table|fun(err:table, room:Room)
---@param callback nil|fun(err:table, room:Room)
function Client:join_by_id(room_id, options_or_callback, callback)
  return self:create_matchmake_request('joinById', room_id, options_or_callback or {}, callback)
end

---@param reconnection_token table
---@param callback fun(err:table, room:Room)
function Client:reconnect(reconnection_token, callback)
  if type(reconnection_token) == "string" and type(callback) == "string" then
    error("DEPRECATED: :reconnect() now only accepts 'reconnection_token' as argument.\nYou can get this token from previously connected `room.reconnection_token`")
  end

  return self:create_matchmake_request('reconnect', reconnection_token.room_id, {
    reconnectionToken = reconnection_token.reconnection_token
  }, callback)
end

---@private
function Client:create_matchmake_request(method, room_name, options_or_callback, callback)
  local options = nil

  if type(options_or_callback) == "function" then
    callback = options_or_callback
    options = {}
  else
    options = options_or_callback
  end

  self.http:request('POST', "matchmake/" .. method .. "/" .. room_name, { body = options, }, function(err, response)
    if (err) then return callback(err) end

    -- forward reconnection token during "reconnect" methods.
    if method == "reconnect" then
      response.reconnectionToken = options_or_callback.reconnectionToken
    end

    self:consume_seat_reservation(response, callback)
  end)
end

---@param response table
---@param callback fun(err:table, room:Room)
---@param reuse_room_instance nil|Room
function Client:consume_seat_reservation(response, callback, reuse_room_instance)
  local room = Room.new(response.room.name)

  room.room_id = response.room.roomId
  room.session_id = response.sessionId

  local options = { sessionId = room.session_id }

  -- forward "reconnection token" in case of reconnection.
  if response.reconnectionToken ~= nil then
    options.reconnectionToken = response.reconnectionToken
  end

  local target_room = (response.devMode and reuse_room_instance) or room

  local _self = self
  room:connect(self.http:_get_ws_endpoint(response.room, options), response.devMode and function()
    print("[Colyseus devMode]: Re-establishing connection with room id '" .. room.room_id .. "'...")

    local retry_count = 0
    local max_retry_count = 8

    local function retry_connection()
      retry_count = retry_count + 1

      -- async check
      _self:consume_seat_reservation(response, function(err, room)
        if err == nil and room ~= nil then
          print("[Colyseus devMode]: Successfully re-established connection with room " .. room.room_id)
        else
          if retry_count < max_retry_count then
            print("[Colyseus devMode]: retrying... (" .. retry_count .. " out of " .. max_retry_count .. ")")
            timer.delay(2, false, retry_connection)
          else
            print("[Colyseus devMode]: Failed to reconnect. Is your server running? Please check server logs.")
          end
        end
      end, target_room)
    end

    -- devMode: try to reconnect after 2 seconds.
    timer.delay(2, false, retry_connection)
  end or nil, target_room)

  local on_join = nil
  local on_error = nil

  on_error = function(err)
    target_room:off('join', on_join)
    callback(err, nil)
  end

  on_join = function()
    target_room:off('error', on_error)
    callback(nil, target_room)
  end

  target_room:once('error', on_error)
  target_room:once('join', on_join)
end

---@param endpoint_or_settings string|{hostname:string, port:number, use_ssl:boolean}
---@return Client
return function (endpoint_or_settings)
  local instance = EventEmitter:new()
  setmetatable(instance, Client)
  instance:init(endpoint_or_settings)
  return instance
end