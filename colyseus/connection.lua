local protocol = require('colyseus.protocol')
local EventEmitter = require('colyseus.eventemitter')

local msgpack = require('colyseus.messagepack.MessagePack')
local websocket_async = require "websocket.client_async"

local connection = {}
connection.config = { connect_timeout = 10 }
connection.__index = connection

function connection.new (endpoint)
  local instance = EventEmitter:new()
  setmetatable(instance, connection)
  instance:init(endpoint)
  return instance
end

function connection:init()
  self._enqueuedCalls = {}
  self.state = "CONNECTING"
  self.is_html5 = sys.get_sys_info().system_name == "HTML5"
end

function connection:loop(timeout)
  if self.ws then
    self.ws:step()
    socket.select(nil, nil, timeout or 0.001)
  end
end

function connection:send(data)
  if self.ws and self.ws.state == "OPEN" then

    if self.is_html5 then
      -- binary frames are sent by default on HTML5
      self.ws:send(data)

    else
      -- force binary frame on native platforms
      self.ws:send(data, 0x2)
    end

  else
    -- WebSocket not connected.
    -- Enqueue data to be sent when readyState is OPEN
    table.insert(self._enqueuedCalls, { 'send', { data } })
  end
end

function connection:open(endpoint)
  self.endpoint = endpoint

  -- skip if connection is already open
  if self.state == 'OPEN' then
    return
  end

  self.ws = websocket_async(self.config or {})

  self.ws:on_connected(function(ok, err)
    self.state = self.ws.state
    if err then
      self:emit("error", err)
      self:emit("close", e)
      self:close()

    else
      for i,cmd in ipairs(self._enqueuedCalls) do
        local method = self[ cmd[1] ]
        local arguments = cmd[2]
        method(self, unpack(arguments))
      end

      self:emit("open")
    end
  end)

  self.ws:on_message(function(message)
    self:emit("message", message)
  end)

  self.ws:on_disconnected(function(e)
    self.state = "CLOSED"
    self:emit("close", e)
  end)

  local ws_protocol = nil
  local ssl_params = nil

  if string.find(endpoint, "wss://") ~= nil then
    ssl_params = {
      mode = "client",
      protocol = "tlsv1_2",
      verify = "none",
      options = "all",
    }
  end

  self.ws:connect(endpoint, ws_protocol, ssl_params)
end

function connection:close()
  self.state = "CLOSED"
  if self.ws then
    self.ws:close()
    self.ws = nil
  end
end

return connection
