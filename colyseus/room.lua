local os = require('os')
local bit = require('colyseus.serializer.bit')
local msgpack = require('colyseus.messagepack.MessagePack')

local Connection = require('colyseus.connection')
local protocol = require('colyseus.protocol')

local EventEmitter = require('colyseus.eventemitter')
local utils = require('colyseus.utils.utils')
local decode = require('colyseus.serializer.schema.encoding.decode')
local encode = require('colyseus.serializer.schema.encoding.encode')
local serialization = require('colyseus.serialization')

local function exponential_backoff(attempt, delay)
  return math.floor(math.pow(2, attempt) * delay)
end

--- Writes a message type (string via the schema codec, or numeric code).
local function write_message_type(initial_bytes, message_type, proto_name)
  local mtype = type(message_type)

  if mtype == "string" then
    encode.string(initial_bytes, message_type)

  elseif mtype == "number" then
    encode.number(initial_bytes, message_type)

  else
    error("Protocol." .. proto_name .. ": message type not supported '" .. tostring(mtype) .. "'")
  end
end

---@class Room : EventEmitterInstance
---@field state table
---@field session_id string
---@field room_id string
---@field connection Connection
Room = {}
Room.__index = function (self, key)
  if key == "state" then
    -- state getter
    return self.serializer:get_state()
  else
    return Room[key]
  end
end

---@private
---@param name string
---@return Room
function Room.new(name)
  local room = EventEmitter:new({
    serializer_id = nil,
    reconnection_token = nil,
    previous_code = nil
  })
  setmetatable(room, Room)
  room:init(name)
  return room
end

---@private
---@param name string
function Room:init(name)
  self.name = name
  self.serializer = nil
  self.on_message_handlers = {}

  self.reconnection = {
    enabled = true,
    retry_count = 0,
    max_retries = 15,
    delay = 100,
    min_delay = 100,
    max_delay = 5000,
    min_uptime = 5000,
    backoff = exponential_backoff,
    max_enqueued_messages = 10,
    enqueued_messages = {},
    is_reconnecting = false
  }

  -- request/response (ROOM_REQUEST / ROOM_RESPONSE) correlation state
  self._pending_requests = {}
  self._next_request_id = 0

  local room = self

  -- remove all listeners on leave
  self:on('leave', function()
    room:destroy()
    room:off()
  end)
end

---@private
---@param endpoint string
---@param options table
function Room:connect (endpoint, options)
  self.connection = Connection.new()

  local room = self

  self.connection:on("message", function(message)
    room:_on_batch_message(message)
  end)

  self.connection:on("close", function(e)
    -- in-flight requests can't be answered on a closed socket
    room:_reject_all_pending_requests("connection closed before a response was received.")

    if (room._joined_at_time == nil) then
      print("Room connection closed before JOIN_ROOM")
      return
    end

    if (
      e.code == protocol.CLOSE_CODE.NO_STATUS_RECEIVED
      or e.code == protocol.CLOSE_CODE.ABNORMAL_CLOSURE
      or e.code == protocol.CLOSE_CODE.GOING_AWAY
      or e.code == protocol.CLOSE_CODE.MAY_TRY_RECONNECT
    ) then
      room:emit("drop", e)
      room:_handle_reconnection(e.code)

    else
      room:emit("leave", e)
    end
  end)

  room.connection:on("error", function(e)
    room:emit("error", e)
  end)

  -- TODO: support "?skipHandshake=1" option here!
  room.connection:open(endpoint)
end

---@param type string
---@param handler fun(message:table)
function Room:on_message(type, handler)
  local _self = self

  local message_type = self:get_message_handler_key(type)
  self.on_message_handlers[message_type] = handler

  return function()
    _self.on_message_handlers[message_type] = nil
  end
end

---@private
function Room:_on_batch_message(binary_string)
  local total_bytes = #binary_string
  local cursor = { offset = 1 }
  while cursor.offset <= total_bytes do
    self:_on_message(binary_string, cursor)
  end
end

---@private
function Room:_on_message (binary_string, it)
  local message = utils.string_to_byte_array(binary_string)

  -- Strip modifier bits (bits 5..7) so the dispatch below stays
  -- modifier-agnostic; consume any modifier-attached prefix bytes here.
  local raw_byte = message[it.offset]
  it.offset = it.offset + 1

  local code = bit.band(raw_byte, protocol.CODE_MASK)

  if bit.band(raw_byte, protocol.MODIFIER_TIMED) ~= 0 then
    -- [uint32 sNow][uint32 inputSeq] — server time (ms since room start) +
    -- last PROCESSED input seq. Consumed here; feeds the room clock + input
    -- ack once the input layer is ported.
    decode.uint32(message, it)
    decode.uint32(message, it)
  end

  if code == protocol.JOIN_ROOM then
    local reconnection_token = decode.string(message, it)
    self.serializer_id = decode.string(message, it)

    self.reconnection_token = {
      room_id = self.room_id,
      reconnection_token = reconnection_token,
    }

    -- Only create a new serializer on first join.
    -- When reconnecting with "skipHandshake=1", we reuse the existing serializer
    if self.serializer == nil then
      local serializer = serialization.get_serializer(self.serializer_id)
      if not serializer then error("missing serializer: " .. self.serializer_id); end
      self.serializer = serializer:new()
    end

    -- State reflection is length-prefixed: the schema handshake must not
    -- read past it into the trailing tagged-section bytes. A zero length
    -- means reconnect (the serializer already has state).
    local state_reflection_len = decode.number(message, it)
    if state_reflection_len > 0 and self.serializer.handshake ~= nil then
      local reflection_end = it.offset + state_reflection_len
      -- bounded slice — the reflection decoder reads until end-of-array
      local reflection_bytes = {}
      for i = 1, reflection_end - 1 do reflection_bytes[i] = message[i] end
      self.serializer:handshake(reflection_bytes, it)
      it.offset = reflection_end
    else
      it.offset = it.offset + state_reflection_len
    end

    -- Trailing tagged sections: [tag byte][length varint][payload].
    -- Unknown tags are skipped via length (forward-compatible).
    -- INPUT_REFLECTION / INPUT_OPTIONS are consumed by the input layer
    -- once ported.
    while it.offset <= #message do
      it.offset = it.offset + 1 -- tag (see protocol.HANDSHAKE_SECTION)
      local section_len = decode.number(message, it)
      it.offset = it.offset + section_len
    end

    -- emit join OR reconnect event
    if self._joined_at_time == nil then
      self._joined_at_time = os.time()
      self:emit("join")

    else
      self.reconnection.is_reconnecting = false
      self:emit("reconnect", self.reconnection.retry_count)
    end

    -- acknowledge JOIN_ROOM
    self.connection:send(utils.byte_array_to_string({ protocol.JOIN_ROOM, 0 })) -- 0 is necessary for HTML5 builds (null-terminated string)

    -- send enqueued messages
    if #self.reconnection.enqueued_messages > 0 then
      for _, msg in ipairs(self.reconnection.enqueued_messages) do
        self.connection:send(msg.data)
      end
      self.reconnection.enqueued_messages = {}
    end

  elseif code == protocol.ERROR then
    local code = decode.number(message, it)
    local error = decode.string(message, it)
    self:emit("error", { code = code, error = error })

  elseif code == protocol.LEAVE_ROOM then
    self:leave()

  elseif code == protocol.ROOM_STATE then
    self:set_state(message, it)

  elseif code == protocol.ROOM_STATE_PATCH then
    self:patch(message, it)

  elseif code == protocol.ROOM_DATA then
    local message_type

    if decode.string_check(message, it) then
      message_type = decode.string(message, it)
    else
      message_type = decode.number(message, it)
    end

    local payload = nil

    if #binary_string >= it.offset then
      local msgpack_cursor = {
          s = binary_string,
          i = it.offset,
          j = #binary_string,
          underflow = function() error "missing bytes" end,
      }
      payload = msgpack.unpack_cursor(msgpack_cursor)
      it.offset = msgpack_cursor.i
    end

    self:_dispatch_message(message_type, payload)

  elseif code == protocol.ROOM_DATA_BYTES then
    local message_type

    if decode.string_check(message, it) then
      message_type = decode.string(message, it)
    else
      message_type = decode.number(message, it)
    end

    local payload = {}
    for i = it.offset, #binary_string, 1 do
      payload[#payload+1] = message[i]
    end

    self:_dispatch_message(message_type, payload)

  elseif code == protocol.ROOM_RESPONSE then
    -- reply to a pending request()
    local request_id = decode.number(message, it)
    local status = message[it.offset]
    it.offset = it.offset + 1

    local payload = nil
    if #binary_string >= it.offset then
      local msgpack_cursor = {
          s = binary_string,
          i = it.offset,
          j = #binary_string,
          underflow = function() error "missing bytes" end,
      }
      payload = msgpack.unpack_cursor(msgpack_cursor)
      it.offset = msgpack_cursor.i
    end

    local entry = self._pending_requests[request_id]
    -- already answered (e.g. timed out) or unknown id — ignore
    if entry ~= nil then
      self._pending_requests[request_id] = nil
      -- the ONE place the wire's three statuses collapse to (ok, payload, faulted):
      entry.on_reply(
        status == protocol.RESPONSE_STATUS.OK,
        payload,
        status == protocol.RESPONSE_STATUS.ERROR
      )
    end

  elseif code == protocol.PING then
    if self.ping_callback then
      local now = os.time()
      self.ping_callback(math.floor((now - self.last_ping_time) + 0.5))
      self.ping_callback = nil
    end
  end
end

---@private
function Room:set_state (encoded_state, it)
  self.serializer:set_state(encoded_state, it)
  self:emit("statechange", self.serializer:get_state())
end

---@private
function Room:patch (binary_patch, it)
  self.serializer:patch(binary_patch, it)
  self:emit("statechange", self.serializer:get_state())
end

---@private
function Room:_handle_reconnection(code)
  if not self.reconnection.enabled then
    self:emit("leave", { code = code })
    return
  end

  if (os.time() - self._joined_at_time) < (self.reconnection.min_uptime / 1000) then
     print(string.format("[Colyseus reconnection]: ❌ Room has not been up for long enough for automatic reconnection. (min uptime: %dms)", self.reconnection.min_uptime))
     self:emit("leave", { code = protocol.CLOSE_CODE.ABNORMAL_CLOSURE })
     return
  end

  if not self.reconnection.is_reconnecting then
    self.reconnection.retry_count = 0
    self.reconnection.is_reconnecting = true
  end

  self:_retry_reconnection()
end

---@private
function Room:_retry_reconnection()
  if self.reconnection.retry_count >= self.reconnection.max_retries then
    -- No more retries
    print(string.format("[Colyseus reconnection]: ❌ Reconnection failed after %d attempts.", self.reconnection.max_retries))
    self.reconnection.is_reconnecting = false
    self:emit("leave", { code = protocol.CLOSE_CODE.FAILED_TO_RECONNECT })
    return
  end

  self.reconnection.retry_count = self.reconnection.retry_count + 1

  local delay_ms = math.min(self.reconnection.max_delay, math.max(self.reconnection.min_delay, self.reconnection.backoff(self.reconnection.retry_count, self.reconnection.delay)))
  local delay_sec = delay_ms / 1000

  print(string.format("[Colyseus reconnection]: ⏳ will retry in %.1f seconds...", delay_sec))

  local room = self

  local on_error = nil
  local on_open = nil

  on_error = function(e)
    room.connection:off("error", on_error)
    room:_retry_reconnection()
  end

  on_open = function()
    room.connection:off("open", on_open)
    room.connection:off("error", on_error)
  end

  timer.delay(delay_sec, false, function()
    print(string.format("[Colyseus reconnection]: 🔄 Re-establishing sessionId '%s' with roomId '%s'... (attempt %d of %d)", room.session_id, room.room_id, room.reconnection.retry_count, room.reconnection.max_retries))

    room.connection:on("error", on_error)
    room.connection:on("open", on_open)
    room.connection:reconnect({
      reconnectionToken = room.reconnection_token.reconnection_token,
      skipHandshake = 1 -- we already applied the handshake on first join
    })
  end)
end

---@private
function Room:_enqueue_message(message)
  table.insert(self.reconnection.enqueued_messages, { data = message })
  if #self.reconnection.enqueued_messages > self.reconnection.max_enqueued_messages then
    table.remove(self.reconnection.enqueued_messages, 1)
  end
end

---@param consented nil|boolean
function Room:leave(consented)
  if self.connection.state == "OPEN" then
    if consented or consented == nil then
      self.connection:send(utils.byte_array_to_string({ protocol.LEAVE_ROOM, 0 }))
    else
      self.connection:close()
    end
  else
    self:emit("leave")
  end
end

function Room:ping(callback)
  -- skip if connection is not open
  if self.connection.state ~= "OPEN" then
    return
  end

  self.last_ping_time = os.time()
  self.ping_callback = callback
  self.connection:send(utils.byte_array_to_string({ protocol.PING }))
end

---@private
--- Transmits `data`, or buffers it while the connection is not open.
function Room:_send_or_enqueue(data)
  if self.connection.state ~= "OPEN" then
    self:_enqueue_message(data)
  else
    self.connection:send(data)
  end
end

---@param message_type number|string
---@param message table|boolean|number|string
function Room:send (message_type, message)
  local initial_bytes = { protocol.ROOM_DATA }
  write_message_type(initial_bytes, message_type, "ROOM_DATA")

  local encoded = (message ~= nil) and msgpack.pack(message) or ''

  self:_send_or_enqueue(utils.byte_array_to_string(initial_bytes) .. encoded)
end

---@param message_type string
---@param bytes table
function Room:send_bytes (message_type, bytes)
  local initial_bytes = { protocol.ROOM_DATA_BYTES }
  write_message_type(initial_bytes, message_type, "ROOM_DATA_BYTES")

  self:_send_or_enqueue(utils.byte_array_to_string(initial_bytes) .. utils.byte_array_to_string(bytes))
end

--- Default request() timeout, in milliseconds.
Room.default_request_timeout = 10000

--- Send a message and await the server's reply — the value the server
--- returns from its matching on_message handler.
---
--- The callback receives (response, err); exactly one is non-nil. `err` is
--- set when the handler rejects (the authored reason) or throws
--- ({name, message, code?}), when the connection closes first, or when no
--- reply arrives within `timeout_ms` (default: Room.default_request_timeout).
---@param message_type number|string
---@param payload any
---@param callback fun(response: any, err: any)
---@param timeout_ms number|nil
function Room:request(message_type, payload, callback, timeout_ms)
  if self.connection == nil or self.connection.state ~= "OPEN" then
    callback(nil, "cannot send request '" .. tostring(message_type) .. "': connection is not open.")
    return
  end

  -- the timer lives in this closure — the pending registry stays unaware of
  -- timeouts; the reply callback and on_close both cancel it
  local timer_handle = nil
  local cancel_timer = function()
    if timer_handle ~= nil then
      timer.cancel(timer_handle)
      timer_handle = nil
    end
  end

  local request_id = self:_send_request(message_type, payload,
    function(ok, reply_payload, _faulted)
      cancel_timer()
      if ok then
        callback(reply_payload, nil)
      else
        callback(nil, reply_payload)
      end
    end,
    function(reason)
      cancel_timer()
      callback(nil, reason)
    end)

  -- Defold's `timer` is unavailable in headless/unit contexts — requests
  -- then simply have no timeout
  if timer ~= nil then
    local ms = timeout_ms or Room.default_request_timeout
    timer_handle = timer.delay(ms / 1000, false, function()
      timer_handle = nil
      self._pending_requests[request_id] = nil
      callback(nil, "request '" .. tostring(message_type) .. "' timed out after " .. ms .. "ms.")
    end)
  end
end

---@private
--- Low-level round-trip primitive: registers `on_reply` (called once with
--- the decoded outcome when the server replies) and transmits a
--- ROOM_REQUEST frame. `request()` wraps it with a timeout.
function Room:_send_request(message_type, payload, on_reply, on_close)
  local request_id = self._next_request_id
  self._next_request_id = (self._next_request_id + 1) % 0x100000000 -- uint32 wrap

  local initial_bytes = { protocol.ROOM_REQUEST }
  encode.number(initial_bytes, request_id)
  write_message_type(initial_bytes, message_type, "ROOM_REQUEST")

  local encoded = (payload ~= nil) and msgpack.pack(payload) or ''

  -- reliable + offline: buffer so it flushes on (re)connect
  self:_send_or_enqueue(utils.byte_array_to_string(initial_bytes) .. encoded)

  self._pending_requests[request_id] = { on_reply = on_reply, on_close = on_close }
  return request_id
end

---@private
function Room:_reject_all_pending_requests(reason)
  for _, entry in pairs(self._pending_requests) do
    if entry.on_close ~= nil then entry.on_close(reason) end
  end
  self._pending_requests = {}
end

---@private
function Room:destroy()
  if self.serializer and self.serializer.teardown ~= nil then
    self.serializer:teardown();
  end
end

---@private
function Room:_dispatch_message (message_type, message)
  local type_key = self:get_message_handler_key(message_type);

  if self.on_message_handlers[type_key] then
    self.on_message_handlers[type_key](message);

  elseif self.on_message_handlers['*'] then
    self.on_message_handlers['*'](message_type, message)

  elseif string.sub(type_key, 1, 3) ~= "s__" then -- ignore internal messages
    print('on_message not registered for type "' .. tostring(message_type) .. '".')
  end
end

---@private
function Room:get_message_handler_key(message_type)
  local t = type(message_type)

  if t == "string" then
    return "s" .. message_type
  elseif t == "number" then
    return "i" .. tostring(message_type)
  else
    error("invalid message type.")
  end
end

return Room
