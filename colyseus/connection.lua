local EventEmitter = require('colyseus.eventemitter')
local protocol = require('colyseus.protocol')
local utils = require('colyseus.utils.utils')

---@class Connection : EventEmitterInstance
---@field state "CONNECTING"|"OPEN"|"CLOSING"|"CLOSED"
local Connection = {}
Connection.config = { connect_timeout = 10 }
Connection.__index = Connection

---@return Connection
function Connection.new()
  local instance = EventEmitter:new()
  setmetatable(instance, Connection)
  instance:init()
  return instance
end

function Connection:init()
  self.state = "CONNECTING"
end

function Connection:send(data)
  if self.state ~= "OPEN" then
    if self.state == "CONNECTING" then
      print("[Colyseus] connection hasn't been established. You shouldn't be sending messages yet.")
    end
    return
  end
  -- the socket can close before its DISCONNECTED event reaches Lua, and the
  -- extension throws on a send in that window
  if not pcall(websocket.send, self.ws, data) then
    self.state = "CLOSING"
  end
end

---@function
---@param endpoint string
function Connection:open(endpoint)
  -- skip if connection is already open
  if self.state == 'OPEN' then return end
  self.endpoint = endpoint
  self:_connect(endpoint, {})
end

function Connection:reconnect(query_params)
  local endpoint = self.endpoint

  -- replace reconnectionToken and skipHandshake query params
  endpoint = string.gsub(endpoint, "reconnectionToken=[^&]*", "")
  endpoint = string.gsub(endpoint, "skipHandshake=[^&]*", "")
  -- cleanup empty params
  endpoint = string.gsub(endpoint, "[?&]+$", "")
  endpoint = string.gsub(endpoint, "&&", "&")

  local query_parts = {}
  for k, v in pairs(query_params) do
    table.insert(query_parts, k .. "=" .. v)
  end

  self:_connect(endpoint .. "&" .. utils.concat(query_parts, "&"), {})
end

function Connection:close(close_code)
  self._force_close_code = close_code -- used for testing reconnection
  self.state = "CLOSED"
  -- socket already gone: closed, or between reconnection attempts
  if self.ws == nil then return end
  websocket.disconnect(self.ws)
  self.ws = nil
end

function Connection:_connect(endpoint, params)
  local this = self
  local opened = false
  self.state = "CONNECTING"
  self.ws = websocket.connect(endpoint, params, function(self, conn, data)
    if data.event == websocket.EVENT_DISCONNECTED then
      -- the extension reports a drop with no close frame as 0; our own close() keeps it
      if data.code == 0 and this.state ~= "CLOSED" then
        data.code = protocol.CLOSE_CODE.ABNORMAL_CLOSURE
      end
      this.state = "CLOSED"

      if this._force_close_code ~= nil then
        data.code = this._force_close_code
        this._force_close_code = nil
      end

      this.ws = nil -- before emitting: a "close" listener may call close()
      this:emit("close", data, opened)

    elseif data.event == websocket.EVENT_CONNECTED then
      -- closed while connecting: HTML5 can't abort a connecting socket, so close it now
      if this.state == "CLOSED" then
        websocket.disconnect(conn)
        return
      end
      opened = true
      print("[Colyseus] websocket connected ")
      this.state = "OPEN"
      this:emit("open")

    elseif data.event == websocket.EVENT_ERROR then
      print("[Colyseus] websocket error")
      this:emit("error", data)

    elseif data.event == websocket.EVENT_MESSAGE then
      this:emit("message", data.message)
    end
  end)
end

return Connection
