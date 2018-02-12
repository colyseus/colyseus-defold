local protocol = require('colyseus.protocol')
local EventEmitter = require('colyseus.events').EventEmitter

local msgpack = require('colyseus.messagepack.MessagePack')
-- local websocket_async = require "defnet.websocket.client_async"
-- local websocket_async = require "websocket.client_sync"

local connection = {}
connection.__index = connection

function connection.new (endpoint)
  local instance = EventEmitter:new()
  setmetatable(instance, connection)
  instance:init(endpoint)
  return instance
end

function connection:init(endpoint)
  self._enqueuedCalls = {}

  -- local is_html5 = sys.get_sys_info().system_name == "HTML5"
  local is_html5 = true
  self.ws = websocket_async(is_html5)

  self.ws:on_connected(function(ok, err)
    print("connected!")

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
    print("on_message triggered successfully!")
    self:emit("message", message)
  end)

  self.ws:connect(endpoint)
  print("ws:connect")
  print(endpoint)
end

function connection:loop(data)
  if self.ws then
    self.ws:step()
  end
end

function connection:send(data)
  if self.ws and self.ws.state == "OPEN" then
    self.ws:send( msgpack.pack(data) )

  else
    -- WebSocket not connected.
    -- Enqueue data to be sent when readyState is OPEN
    table.insert(self._enqueuedCalls, { 'send', { data } })
  end
end

function connection:close()
  self.ws:close()
  self.ws = nil
end

return connection
