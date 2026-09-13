--
-- Room/Connection lifecycle around the socket closing, through the real
-- Connection + Room:connect wiring over a stub of the websocket extension.
--
local protocol = require 'colyseus.protocol'
local Connection = require 'colyseus.connection'
local Room = require 'colyseus.room'

--- Swap the extension's `websocket` global for a stub while `fn` runs.
--- `fire(event, data)` delivers an event the way the engine would; setting
--- `ws.closed` makes `send` throw like the extension does on a closed socket.
local function with_websocket(fn)
  local original = websocket
  local ws = { EVENT_CONNECTED = 0, EVENT_DISCONNECTED = 1, EVENT_MESSAGE = 2, EVENT_ERROR = 3, sent = {} }
  local callback
  function ws.connect(_, _, cb) callback = cb; return {} end
  function ws.send(_, data)
    if ws.closed then error("Connection isn't connected") end
    table.insert(ws.sent, data)
  end
  function ws.disconnect() end
  local function fire(event, data)
    data = data or {}
    data.event = event
    callback(nil, nil, data)
  end
  _G.websocket = ws
  local ok, err = pcall(fn, ws, fire)
  _G.websocket = original
  if not ok then error(err, 0) end
end

return function()
  describe("room lifecycle", function()

    it("a second leave while the first is in flight is a no-op", function()
      with_websocket(function(ws, fire)
        local room = Room.new("lifecycle")
        room:connect("ws://localhost:2567/lifecycle?sessionId=s1", {})
        fire(ws.EVENT_CONNECTED)
        room._joined_at_time = 1 -- past JOIN_ROOM

        local leaves = {}
        room:on("leave", function(e) table.insert(leaves, e) end)

        room:leave()
        assert_equal(1, #ws.sent)
        assert_equal(protocol.LEAVE_ROOM, ws.sent[1]:byte(1))

        -- the server has closed the socket; DISCONNECTED hasn't reached Lua yet
        ws.closed = true
        room:leave()
        room:leave(false)
        assert_equal(1, #ws.sent)
        assert_equal(0, #leaves)

        fire(ws.EVENT_DISCONNECTED, { code = protocol.CLOSE_CODE.CONSENTED })
        assert_equal(1, #leaves)
        assert_equal(protocol.CLOSE_CODE.CONSENTED, leaves[1].code)
      end)
    end)

    it("a send racing the socket closing doesn't throw", function()
      with_websocket(function(ws, fire)
        local conn = Connection.new()
        conn:open("ws://localhost:2567/x")
        fire(ws.EVENT_CONNECTED)
        conn:send("a")
        assert_equal(1, #ws.sent)

        ws.closed = true
        conn:send("b")
        assert_equal("CLOSING", conn.state)

        -- later sends are dropped without reaching the dying socket
        ws.closed = false
        conn:send("c")
        assert_equal(1, #ws.sent)

        local closes = 0
        conn:on("close", function() closes = closes + 1 end)
        fire(ws.EVENT_DISCONNECTED, { code = 1006 })
        assert_equal("CLOSED", conn.state)
        assert_equal(1, closes)
      end)
    end)

  end)
end
