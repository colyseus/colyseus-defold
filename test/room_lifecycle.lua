--
-- Room/Connection lifecycle around the socket closing, through the real
-- Connection + Room:connect wiring over a stub of the websocket extension.
--
local telescope = require 'deftest.telescope'
local protocol = require 'colyseus.protocol'
local Connection = require 'colyseus.connection'
local Room = require 'colyseus.room'

--- A stand-in for Defold's `timer`: nothing fires until `flush()`, which runs
--- every pending callback, and any they schedule, in the order scheduled.
local function manual_timer()
  local clock, pending, last_handle = {}, {}, 0
  function clock.delay(_, _, callback)
    last_handle = last_handle + 1
    pending[last_handle] = callback
    return last_handle
  end
  function clock.cancel(handle)
    pending[handle] = nil
  end
  local function flush()
    local handle = 0
    while handle < last_handle do
      handle = handle + 1
      local callback = pending[handle]
      pending[handle] = nil
      if callback then callback(nil, handle, 0) end
    end
  end
  return clock, flush
end

--- Swap the extension's `websocket` global for a stub, and `timer` for a
--- manual one, while `fn` runs. `fire(event, data)` delivers an event to the
--- newest socket the way the engine would; `flush()` fires the pending timers.
--- Setting `ws.closed` makes `send` throw like the extension does on a closed
--- socket; setting `ws.html5` makes `disconnect` ignore a socket that is still
--- connecting, as that build does.
local function with_websocket(fn)
  local original_websocket, original_timer = websocket, timer
  local ws = { EVENT_CONNECTED = 0, EVENT_DISCONNECTED = 1, EVENT_MESSAGE = 2, EVENT_ERROR = 3, sent = {}, sockets = {} }
  local callback
  function ws.connect(_, _, cb)
    callback = cb
    table.insert(ws.sockets, {})
    return ws.sockets[#ws.sockets]
  end
  function ws.send(_, data)
    if ws.closed then error("Connection isn't connected") end
    table.insert(ws.sent, data)
  end
  function ws.disconnect(socket)
    if socket == nil then error("The first argument must be a valid connection!") end
    if ws.html5 and not socket.open then return end
    socket.disconnected = true
  end
  local function fire(event, data)
    data = data or {}
    data.event = event
    if event == ws.EVENT_CONNECTED then ws.sockets[#ws.sockets].open = true end
    callback(nil, ws.sockets[#ws.sockets], data)
  end

  local clock, flush = manual_timer()
  _G.websocket, _G.timer = ws, clock
  local ok, err = pcall(fn, ws, fire, flush)
  _G.websocket, _G.timer = original_websocket, original_timer
  if not ok then error(err, 0) end
end

--- Records what the room emits, by event. Spies on emit itself: the room
--- unhooks listeners on its first "leave", which would hide a second one.
local function record(room)
  local seen = setmetatable({}, { __index = function(t, event) t[event] = {}; return t[event] end })
  local emit = room.emit
  room.emit = function(self, event, e, ...)
    table.insert(seen[event], e or {})
    return emit(self, event, e, ...)
  end
  return seen
end

--- A room past JOIN_ROOM, up long enough to auto-reconnect, and the record of
--- what it emits.
local function joined_room(ws, fire)
  local room = Room.new("lifecycle")
  room.room_id = "r1"
  room.session_id = "s1"
  room:connect("ws://localhost:2567/r1?sessionId=s1", {})
  fire(ws.EVENT_CONNECTED)
  room._joined_at_time = 1
  room.reconnection_token = { room_id = "r1", reconnection_token = "tokA" }
  room.serializer = { get_state = function() return nil end }
  return room, record(room)
end

--- A joined room that dropped and is dialing its first reconnection attempt.
local function reconnecting_room(ws, fire, flush)
  local room, seen = joined_room(ws, fire)
  fire(ws.EVENT_DISCONNECTED, { code = protocol.CLOSE_CODE.ABNORMAL_CLOSURE })
  flush()
  return room, seen
end

-- deftest injects its assertions into the `it` body's environment, so a helper
-- defined out here can't reach them; registered as an assertion instead.
telescope.make_assertion("left",
  function(_, seen, code)
    local codes = {}
    for i, e in ipairs(seen.leave) do codes[i] = tostring(e.code) end
    return telescope.assertion_message_prefix ..
      ("one leave with code %s, got {%s}"):format(tostring(code), table.concat(codes, ","))
  end,
  function(seen, code)
    return #seen.leave == 1 and seen.leave[1].code == code
  end)

-- JOIN_ROOM answering a reconnection: token "tokB", serializer "schema", no reflection
local RECONNECT_JOIN = string.char(10, 4, 116, 111, 107, 66, 6, 115, 99, 104, 101, 109, 97, 0)

return function()
  describe("room lifecycle", function()

    it("a second leave while the first is in flight is a no-op", function()
      with_websocket(function(ws, fire)
        local room, seen = joined_room(ws, fire)

        room:leave()
        assert_equal(1, #ws.sent)
        assert_equal(protocol.LEAVE_ROOM, ws.sent[1]:byte(1))

        -- the server has closed the socket; DISCONNECTED hasn't reached Lua yet
        ws.closed = true
        room:leave()
        room:leave(false)
        assert_equal(1, #ws.sent)
        assert_equal(0, #seen.leave)

        fire(ws.EVENT_DISCONNECTED, { code = protocol.CLOSE_CODE.CONSENTED })
        assert_left(seen, protocol.CLOSE_CODE.CONSENTED)
      end)
    end)

    it("leave() racing the server's close keeps the server's code", function()
      with_websocket(function(ws, fire)
        local room, seen = joined_room(ws, fire)

        -- the server kicked the client; DISCONNECTED hasn't reached Lua yet
        ws.closed = true
        room:send("move", {})
        room:leave()
        assert_equal(0, #seen.leave)

        fire(ws.EVENT_DISCONNECTED, { code = 4321 })
        assert_left(seen, 4321)
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

    it("a socket reported open twice opens once", function()
      with_websocket(function(ws, fire)
        local conn = Connection.new()
        local opens = 0
        conn:on("open", function() opens = opens + 1 end)
        conn:open("ws://localhost:2567/x")

        -- HTML5 reports it from onopen, then again on the next update
        fire(ws.EVENT_CONNECTED)
        fire(ws.EVENT_CONNECTED)
        assert_equal(1, opens)
        assert_equal("OPEN", conn.state)
      end)
    end)

    it("a drop without a close frame reconnects", function()
      with_websocket(function(ws, fire, flush)
        local room, seen = joined_room(ws, fire)

        -- native reports a lost connection as an error, then a close with code 0
        fire(ws.EVENT_ERROR)
        fire(ws.EVENT_DISCONNECTED, { code = 0 })
        assert_equal(0, #seen.leave)
        assert_equal(1, #seen.drop)
        assert_equal(protocol.CLOSE_CODE.ABNORMAL_CLOSURE, seen.drop[1].code)

        flush()
        assert_equal(2, #ws.sockets)
        assert_equal(true, room.reconnection.is_reconnecting)
      end)
    end)

  end)

  describe("room leave while the connection is down", function()

    it("leave() while waiting to retry cancels the retry", function()
      with_websocket(function(ws, fire, flush)
        local room, seen = joined_room(ws, fire)
        fire(ws.EVENT_DISCONNECTED, { code = protocol.CLOSE_CODE.ABNORMAL_CLOSURE })
        assert_equal(true, room.reconnection.is_reconnecting)

        room:leave()
        assert_left(seen, protocol.CLOSE_CODE.CONSENTED)
        assert_equal(false, room.reconnection.is_reconnecting)

        flush()
        assert_equal(1, #ws.sockets)
      end)
    end)

    it("leave() aborts a reconnection attempt that is still connecting", function()
      with_websocket(function(ws, fire, flush)
        local room, seen = reconnecting_room(ws, fire, flush)
        assert_equal(2, #ws.sockets)
        assert_equal("CONNECTING", room.connection.state)

        room:leave()
        assert_left(seen, protocol.CLOSE_CODE.CONSENTED)
        assert_equal(true, ws.sockets[2].disconnected)

        -- the aborted attempt reports back, whatever its close code
        fire(ws.EVENT_ERROR)
        fire(ws.EVENT_DISCONNECTED, { code = protocol.CLOSE_CODE.ABNORMAL_CLOSURE })
        flush()
        assert_equal(1, #seen.leave)
        assert_equal(1, #seen.drop)
        assert_equal(0, #seen.error)
        assert_equal(2, #ws.sockets)
      end)
    end)

    it("a reconnection attempt that opens after leave() doesn't revive the room", function()
      with_websocket(function(ws, fire, flush)
        ws.html5 = true
        local room, seen = reconnecting_room(ws, fire, flush)

        room:leave()
        fire(ws.EVENT_CONNECTED) -- HTML5 couldn't abort it
        assert_equal("CLOSED", room.connection.state)
        assert_equal(true, ws.sockets[2].disconnected)
        room:send("move", {})
        assert_equal(0, #ws.sent)

        -- a frame queued alongside the open still arrives
        fire(ws.EVENT_MESSAGE, { message = RECONNECT_JOIN })
        assert_equal(0, #seen.reconnect)
        assert_equal(0, #ws.sent)

        fire(ws.EVENT_DISCONNECTED, { code = protocol.CLOSE_CODE.NORMAL_CLOSURE })
        assert_left(seen, protocol.CLOSE_CODE.CONSENTED)
      end)
    end)

    it("leave() closes an attempt that opened but hasn't rejoined", function()
      with_websocket(function(ws, fire, flush)
        local room, seen = reconnecting_room(ws, fire, flush)
        fire(ws.EVENT_CONNECTED) -- JOIN_ROOM not here yet

        room:leave()
        assert_left(seen, protocol.CLOSE_CODE.CONSENTED)
        assert_equal(true, ws.sockets[2].disconnected)
        assert_equal(0, #ws.sent)

        fire(ws.EVENT_MESSAGE, { message = RECONNECT_JOIN })
        fire(ws.EVENT_DISCONNECTED, { code = protocol.CLOSE_CODE.NORMAL_CLOSURE })
        assert_equal(0, #seen.reconnect)
        assert_equal(1, #seen.leave)
      end)
    end)

    it("leave() from a drop listener doesn't reconnect", function()
      with_websocket(function(ws, fire, flush)
        local room, seen = joined_room(ws, fire)
        room:on("drop", function() room:leave() end)

        fire(ws.EVENT_DISCONNECTED, { code = protocol.CLOSE_CODE.ABNORMAL_CLOSURE })
        assert_left(seen, protocol.CLOSE_CODE.CONSENTED)
        assert_equal(0, room.reconnection.retry_count)
        assert_equal(false, room.reconnection.is_reconnecting)

        flush()
        assert_equal(1, #ws.sockets)
      end)
    end)

    it("leaving from a drop listener doesn't disconnect the socket that dropped", function()
      -- leave(false) on any drop
      with_websocket(function(ws, fire)
        local room, seen = joined_room(ws, fire)
        room:on("drop", function() room:leave(false) end)

        fire(ws.EVENT_DISCONNECTED, { code = protocol.CLOSE_CODE.ABNORMAL_CLOSURE })
        assert_equal(1, #seen.leave)
        assert_nil(ws.sockets[1].disconnected)
      end)

      -- leave() on the drop of an attempt that opened but hasn't rejoined
      with_websocket(function(ws, fire, flush)
        local room, seen = reconnecting_room(ws, fire, flush)
        fire(ws.EVENT_CONNECTED)
        room:on("drop", function() room:leave() end)

        fire(ws.EVENT_DISCONNECTED, { code = protocol.CLOSE_CODE.ABNORMAL_CLOSURE })
        assert_left(seen, protocol.CLOSE_CODE.CONSENTED)
        assert_nil(ws.sockets[2].disconnected)
      end)
    end)

    it("a drop after LEAVE_ROOM was sent ends the room instead of reconnecting", function()
      with_websocket(function(ws, fire, flush)
        local room, seen = joined_room(ws, fire)

        room:leave()
        assert_equal(protocol.LEAVE_ROOM, ws.sent[1]:byte(1))

        -- the socket dies before the server closes it
        fire(ws.EVENT_DISCONNECTED, { code = protocol.CLOSE_CODE.ABNORMAL_CLOSURE })
        assert_left(seen, protocol.CLOSE_CODE.CONSENTED)
        assert_equal(0, #seen.drop)

        flush()
        assert_equal(1, #ws.sockets)
      end)
    end)

    it("leave() on a room that already left doesn't fire leave again", function()
      with_websocket(function(ws, fire)
        local room, seen = joined_room(ws, fire)

        fire(ws.EVENT_DISCONNECTED, { code = 4321 })
        assert_left(seen, 4321)

        room:leave()
        assert_left(seen, 4321)
      end)
    end)

    it("running out of retries fires leave once", function()
      with_websocket(function(ws, fire, flush)
        local room, seen = joined_room(ws, fire)
        room.reconnection.max_retries = 2
        fire(ws.EVENT_DISCONNECTED, { code = protocol.CLOSE_CODE.ABNORMAL_CLOSURE })

        for _ = 1, 2 do
          flush()
          -- the server is unreachable
          fire(ws.EVENT_ERROR)
          fire(ws.EVENT_DISCONNECTED, { code = 0 })
        end

        assert_left(seen, protocol.CLOSE_CODE.FAILED_TO_RECONNECT)
        assert_equal(false, room.reconnection.is_reconnecting)

        flush()
        assert_equal(3, #ws.sockets)
      end)
    end)

    it("a failed attempt whose close comes before its error retries once", function()
      with_websocket(function(ws, fire, flush)
        local _, seen = reconnecting_room(ws, fire, flush)

        fire(ws.EVENT_DISCONNECTED, { code = 0 })
        fire(ws.EVENT_ERROR)
        assert_equal(0, #seen.leave)

        flush()
        assert_equal(3, #ws.sockets)
      end)
    end)

    it("a failed attempt doesn't unhook the room's error listener", function()
      with_websocket(function(ws, fire, flush)
        local _, seen = reconnecting_room(ws, fire, flush)
        fire(ws.EVENT_ERROR)
        fire(ws.EVENT_DISCONNECTED, { code = 0 })

        flush()
        fire(ws.EVENT_CONNECTED)
        fire(ws.EVENT_MESSAGE, { message = RECONNECT_JOIN })
        assert_equal(1, #seen.reconnect)

        fire(ws.EVENT_ERROR)
        assert_equal(2, #seen.error)
      end)
    end)

    it("leave(false) closes without reconnecting", function()
      with_websocket(function(ws, fire, flush)
        local room, seen = joined_room(ws, fire)

        room:leave(false)
        assert_equal(0, #ws.sent)
        assert_equal(true, ws.sockets[1].disconnected)

        -- native reports a local close as code 0
        fire(ws.EVENT_DISCONNECTED, { code = 0 })
        assert_left(seen, 0)
        assert_equal(0, #seen.drop)

        flush()
        assert_equal(1, #ws.sockets)
      end)
    end)

    it("leave(false) aborts a reconnection attempt that is still connecting", function()
      with_websocket(function(ws, fire, flush)
        local room = reconnecting_room(ws, fire, flush)

        room:leave(false)
        assert_equal(true, ws.sockets[2].disconnected)
      end)
    end)

  end)
end
