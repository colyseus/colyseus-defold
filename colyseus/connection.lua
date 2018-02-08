local protocol = require('colyseus.protocol')
local EventEmitter = require('colyseus.events').EventEmitter

local msgpack = require('colyseus.messagepack.MessagePack')
local websocket_async = require "defnet.websocket.client_async"

Connection = {}
Connection.__index = Connection

function Connection.new (endpoint)
  local instance = EventEmitter:new()
  setmetatable(instance, Connection)
  instance:init(endpoint)
  return instance
end

function Connection:init(endpoint)
  self._enqueuedCalls = {}

  local is_html5 = sys.get_sys_info().system_name == "HTML5"
  self.ws = websocket_async(is_html5)

  self.ws:on_connected(function(ok, err)
    if err then
      self:emit('error', err)
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

  self.ws:connect(endpoint)
  print("ws:connect")
  print(endpoint)
end

function Connection:loop(data)
  if self.ws then
    self.ws:step()
  end
end

function Connection:send(data)
  if self.ws and self.ws.state == "OPEN" then
    self.ws:send( msgpack.pack(data) )

  else
    -- WebSocket not connected.
    -- Enqueue data to be sent when readyState is OPEN
    table.insert(self._enqueuedCalls, { 'send', { data } })
  end
end

function Connection:close()
  self.ws:close()
  self.ws = nil
end

return Connection
