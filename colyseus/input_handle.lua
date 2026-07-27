--
-- Per-room input handle returned by room:input(). Mutate `handle.data`, then
-- call `handle:send()` to delta-encode and transmit. Port of the JS SDK's
-- input/InputHandle.ts — wire contract: PORTING/sdk-ports-input-layer.md
-- ([19|TIMED?][stamp?][body] framing, delta-coded lag-comp stamps, implicit
-- 1-based count seq, ack → RTT sample, replay ring, epoch-counted reset).
--
local protocol = require 'colyseus.protocol'
local utils = require 'colyseus.utils.utils'
local encode = require 'colyseus.serializer.schema.encoding.encode'
local RoomClock = require 'colyseus.room_clock'

local InputHandle = {}
InputHandle.__index = InputHandle

local BUFFER_FLOOR = 64
local BUFFER_RTT_BUDGET_MS = 1000
local BUFFER_HEADROOM = 1.5

---@param data table schema instance (mutate, then send())
---@param encoder table InputEncoder bound to `data`
---@param opts table {stamp_render, stamp_reckon, render_delay, allow_rewind, tick_rate, patch_rate, sub_steps}
---@param get_connection function -> connection (read at send time; survives reconnect)
---@param get_clock function -> RoomClock
--- How far in the PAST this client draws remote entities, in ms. A
--- lag-compensating server rewinds its targets by this much plus half the RTT,
--- so it reads the world at the instant you actually saw — get it wrong and
--- every shot misses by exactly the difference. `predict:make_reconciler()`
--- binds it from the lerp delay you already attached with; set it yourself only
--- to override.
function InputHandle:render_delay()
  return self._render_delay
end

function InputHandle:set_render_delay(ms)
  self._render_delay = math.max(0, ms or 0)
end

function InputHandle.new(data, encoder, opts, get_connection, get_clock)
  local self = setmetatable({}, InputHandle)
  self.data = data
  self.mode = encoder.mode

  --- server-advertised rates (nil when not advertised)
  self.tick_rate = opts.tick_rate
  self.patch_rate = opts.patch_rate
  self.sub_steps = opts.sub_steps or 1
  if self.tick_rate ~= nil then
    self.step_seconds = 1 / self.tick_rate
    self.step_ms = 1000 / self.tick_rate
    self.sub_step_seconds = self.step_seconds / self.sub_steps
    self.sub_step_ms = self.step_ms / self.sub_steps
  end

  --- input round-trip state
  self.sent_count = 0      -- reliable inputs transmitted
  self.last_processed = 0  -- server-acked (consumed count)
  self.epoch = 0           -- reset counter — observing controllers poll this

  self._encoder = encoder
  self._get_connection = get_connection
  self._get_clock = get_clock
  self._stamp_render = opts.stamp_render or false
  self._stamp_reckon = opts.stamp_reckon or false
  self._render_delay = opts.render_delay or 0
  self._allow_rewind = opts.allow_rewind
  self._last_stamp = 0     -- delta-coded stamp baseline
  self._pending_reckon = 0
  self._send_listeners = nil

  -- replay ring sized to worst-case in-flight = (RTT budget + patch interval) × input rate
  local step_ms = self.step_ms or (1000 / 60)
  local window = BUFFER_RTT_BUDGET_MS + (self.patch_rate or 0)
  self.replay_buffer_size = math.max(BUFFER_FLOOR, math.ceil((window / step_ms) * BUFFER_HEADROOM))

  self._send_times = {}
  self._input_buffer = nil  -- lazily allocated snapshot ring
  self._reckon_times = nil  -- per-seq reckon stamps (only when stamping reckon)

  return self
end

--- Sent but not yet acked.
function InputHandle:pending_count()
  return self.sent_count - self.last_processed
end

--- Encode the staged input and send it. Always transmits one input when the
--- connection is open — a body-less frame on a no-change tick. Returns the
--- seq assigned to this input, or 0 when nothing was sent (seqs are 1-based).
function InputHandle:send()
  local conn = self._get_connection()
  if conn == nil or conn.state ~= "OPEN" then return 0 end

  local body = self._encoder:encode()
  local reliable = (self._encoder.mode == "reliable")

  local want_stamp = (self._stamp_reckon or self._stamp_render) and reliable
    and (self._allow_rewind == nil or self._allow_rewind(self.data) == true)
  local both = self._stamp_reckon and self._stamp_render

  local out = {}
  local opcode = reliable and protocol.ROOM_INPUT_RELIABLE or protocol.ROOM_INPUT_UNRELIABLE
  if want_stamp then opcode = opcode + protocol.MODIFIER_TIMED end
  table.insert(out, opcode)

  if want_stamp then
    local clock = self._get_clock()
    local synced = clock ~= nil and clock:last_server_time() > 0
    local rk = synced and math.max(0, math.floor(clock:server_now() + 0.5)) or 0
    self._pending_reckon = rk
    local render_delta = synced
      and math.min(0xffff, math.max(0, math.floor(self._render_delay + clock:smoothed_rtt() / 2 + 0.5)))
      or 0
    -- the mode's single u32 timeline, delta-coded vs the baseline;
    -- BOTH mode trails the absolute u16 renderDelta
    local stamp
    if self._stamp_reckon then
      stamp = rk
    else
      stamp = (rk > render_delta) and (rk - render_delta) or 0
    end
    encode.number(out, stamp - self._last_stamp)
    self._last_stamp = stamp
    if both then encode.uint16(out, render_delta) end
  else
    self._pending_reckon = 0
  end

  for i = 1, #body do table.insert(out, body[i]) end
  -- WS-only transport: unreliable falls back to the reliable channel
  conn:send(utils.byte_array_to_string(out))

  local seq
  if reliable then
    self.sent_count = self.sent_count + 1 -- implicit count seq
    seq = self.sent_count
  else
    self.sent_count = self._encoder.seq   -- adopt the framework seq
    seq = self.sent_count
  end
  self:_record_sent(seq)
  return seq
end

--- Subscribe to sends: listener(seq) fires synchronously at the end of each
--- send() (replay ring + reckon instant already recorded). Returns an
--- unsubscribe function.
function InputHandle:on_send(listener)
  if self._send_listeners == nil then self._send_listeners = {} end
  table.insert(self._send_listeners, listener)
  return function()
    for i, l in ipairs(self._send_listeners) do
      if l == listener then
        table.remove(self._send_listeners, i)
        return
      end
    end
  end
end

--- Reset encoder + round-trip state (the SDK calls this on reconnect): next
--- send emits a full snapshot; the stamp baseline re-zeroes; `epoch`
--- increments so observing controllers self-reset.
function InputHandle:reset()
  self._encoder:reset()
  self.sent_count = self._encoder.seq
  self.last_processed = self._encoder.seq
  self._last_stamp = 0
  self._send_times = {}
  self.epoch = self.epoch + 1
end

--- The buffered snapshot of reliable input `seq` for reconciliation replay.
--- nil if already acked, never sent, or aged out. The instance is REUSED —
--- read synchronously, don't retain.
function InputHandle:at(seq)
  if self._input_buffer == nil then return nil end
  if seq <= self.last_processed or seq > self.sent_count then return nil end
  if self.sent_count - seq >= self.replay_buffer_size then return nil end
  return self._input_buffer[(seq % self.replay_buffer_size) + 1]
end

--- The reckon instant (server-clock ms) stamped onto reliable input `seq`;
--- 0 when reckon stamping is off or `seq` is outside the valid window.
function InputHandle:reckon_time_at(seq)
  if self._reckon_times == nil then return 0 end
  if seq <= self.last_processed or seq > self.sent_count then return 0 end
  if self.sent_count - seq >= self.replay_buffer_size then return 0 end
  return self._reckon_times[(seq % self.replay_buffer_size) + 1] or 0
end

--- Feed the server's last-PROCESSED input seq (decoded from the TIMED
--- prefix). Advances last_processed and returns the RTT sample for that ack,
--- or -1 when unknown (stale seq / aged out / pre-reset send).
function InputHandle:ack_input(seq)
  if seq <= self.last_processed then return -1 end
  local aged = self.sent_count - seq >= self.replay_buffer_size
  self.last_processed = seq
  if aged then return -1 end
  local sent_at = self._send_times[(seq % self.replay_buffer_size) + 1]
  if sent_at ~= nil and sent_at > 0 then
    return RoomClock.get_now() - sent_at
  end
  return -1
end

--- Snapshot the just-sent input + its send time (and reckon stamp) by seq.
function InputHandle:_record_sent(seq)
  if self._input_buffer == nil then
    local class = getmetatable(self.data)
    self._input_buffer = {}
    for i = 1, self.replay_buffer_size do
      self._input_buffer[i] = class:new()
    end
  end
  local slot = (seq % self.replay_buffer_size) + 1
  self._encoder:copy_into(self._input_buffer[slot])
  self._send_times[slot] = RoomClock.get_now()
  if self._stamp_reckon then
    if self._reckon_times == nil then self._reckon_times = {} end
    self._reckon_times[slot] = self._pending_reckon
  end
  if self._send_listeners ~= nil then
    -- iterate a copy — a listener may unsubscribe mid-dispatch
    local listeners = {}
    for i, l in ipairs(self._send_listeners) do listeners[i] = l end
    for _, l in ipairs(listeners) do l(seq) end
  end
end

return InputHandle
