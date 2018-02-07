local protocol = require('colyseus.protocol')
local EventEmitter = require('colyseus.events').EventEmitter

local msgpack = require('MessagePack')
local websocket_async = require "defnet.websocket.client_async"

Connection = {}
Connection.__index = Connection

function Connection.new (endpoint)
  local instance = EventEmitter:new({
    _enqueuedCalls = {}, -- array
  })
  setmetatable(instance, Connection)
  instance:init(endpoint)
  return instance
end

function Connection:init(endpoint)
  local is_html5 = sys.get_sys_info().system_name == "HTML5"

  self.ws = websocket_async(is_html5)

  self.ws:on_connected(function(ok, err)
    log("on connected", ok, err)
    if err then
      self:emit('error', err)

      self.ws:close()
      self.ws = nil

    else
      for i,cmd in ipairs(self._enqueuedCalls) do
        local method = self[ cmd[1] ]
        local arguments = cmd[2]
        method(self, unpack(arguments))
      end

      self:emit('open')
    end
  end)

  self.ws:on_message(function(message)
    self:emit('message', message)
  end)

  self.ws:connect(endpoint)
end

function Connection:send(data)
  if self.ws.state == "OPEN" then
    self.ws:send( msgpack.pack(data), {
      type = WebSocket.BINARY
    } )

  else
    -- WebSocket not connected.
    -- Enqueue data to be sent when readyState is OPEN
    table.insert(self._enqueuedCalls, { 'send', { data } })
  end
end


function Connection:close()
  self.ws:close()
end

return Connection
