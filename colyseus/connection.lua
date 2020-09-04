local EventEmitter = require('colyseus.eventemitter')

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
  self.state = "CONNECTING"
  self.is_html5 = sys.get_sys_info().system_name == "HTML5"
end

function connection:send(data)
  websocket.send(self.ws, data)
end

function connection:open(endpoint)
  -- skip if connection is already open
  if self.state == 'OPEN' then return end

  self.endpoint = endpoint

  local this = self
  local params = {}

  self.ws = websocket.connect(endpoint, params, function(self, conn, data)
    if data.event == websocket.EVENT_DISCONNECTED then
      print("websocket disconnected!")
      this.state = "CLOSED"
      this:emit("close", data)
      this.ws = nil

    elseif data.event == websocket.EVENT_CONNECTED then
      print("websocket connected ")
      this.state = "OPEN"
      this:emit("open")

    elseif data.event == websocket.EVENT_ERROR then
      print("websocket error:", data.error)
      this:emit("error", data.error)

    elseif data.event == websocket.EVENT_MESSAGE then
      this:emit("message", data.message)
    end
  end)
end

function connection:close()
  self.state = "CLOSED"
  websocket.disconnect(self.ws)
  self.ws = nil
end

return connection
