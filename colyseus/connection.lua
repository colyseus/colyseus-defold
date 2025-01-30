local EventEmitter = require('colyseus.eventemitter')

---@class Connection : EventEmitterInstance
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
  self.is_html5 = sys.get_sys_info().system_name == "HTML5"
end

function Connection:send(data)
  if self.state ~= "OPEN" then
    print("[Colyseus] connection hasn't been established. You shouldn't be sending messages yet.")
    return
  end
  websocket.send(self.ws, data)
end

---@function
---@param endpoint string
function Connection:open(endpoint)
  -- skip if connection is already open
  if self.state == 'OPEN' then return end

  self.endpoint = endpoint

  local this = self
  local params = {}

  self.ws = websocket.connect(endpoint, params, function(self, conn, data)
    if data.event == websocket.EVENT_DISCONNECTED then
      this.state = "CLOSED"

      this:emit("close", data)
      this.ws = nil

    elseif data.event == websocket.EVENT_CONNECTED then
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

function Connection:close()
  self.state = "CLOSED"
  websocket.disconnect(self.ws)
  self.ws = nil
end

return Connection
