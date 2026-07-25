--
-- Typed optimistic-event channel (port of the JS SDK's
-- predict/predictedEventChannel.ts): birth in the predicted sim
-- (ctx:predict(channel, payload) — live-only, replay-safe) or from UI
-- (channel:predict(payload)); settlement: confirm() on the authoritative
-- signal, sim-born grace-tick auto-reject, UI-born wall-clock TTL.
--
local RoomClock = require 'colyseus.room_clock'

local PredictedEventChannel = {}
PredictedEventChannel.__index = PredictedEventChannel

-- one anonymous slot for payloads with no derivable key
local SINGLETON_KEY = {}

---@param opts table {on_predict, on_confirm, on_reject, on_unpredicted,
---  unique_by = fun(payload) -> key, grace_ticks = 10, ttl_ms = 0 (max(2*rtt, 600)),
---  cooldown_ms = 0}
---@param clock table|nil RoomClock (serverNow axis for TTL/cooldown)
function PredictedEventChannel.new(opts, clock)
  local self = setmetatable({}, PredictedEventChannel)
  self._opts = opts or {}
  self._clock = clock
  self._entries = {}          -- key -> { payload, seq, acked, at }
  self._pending = 0
  self._cooldown_until = -math.huge
  self.dead = false
  return self
end

function PredictedEventChannel:_now()
  if self._clock ~= nil then return self._clock:server_now() end
  return RoomClock.get_now()
end

function PredictedEventChannel:_key_of(payload)
  if self._opts.unique_by ~= nil then return self._opts.unique_by(payload) end
  local t = type(payload)
  if t == "string" or t == "number" then return payload end
  return SINGLETON_KEY
end

function PredictedEventChannel:pending_count()
  return self._pending
end

--- Sim-born prediction (reached via ctx:predict — live steps only).
function PredictedEventChannel:_predict_from_sim(seq, payload, acked)
  self:_add(seq, payload, acked)
end

--- Predict from OUTSIDE the sim (UI-optimistic; wall-clock TTL).
function PredictedEventChannel:predict(payload)
  self:_add(-1, payload, nil)
end

function PredictedEventChannel:_add(seq, payload, acked)
  local key = self:_key_of(payload)
  if self._entries[key] ~= nil then return end -- pending dedupe
  local t = self:_now()
  local cooldown = self._opts.cooldown_ms or 0
  if cooldown > 0 then
    if t < self._cooldown_until then return end
    self._cooldown_until = t + cooldown
  end
  self._entries[key] = { payload = payload, seq = seq, acked = acked, at = t }
  self._pending = self._pending + 1
  if self._opts.on_predict ~= nil then self._opts.on_predict(payload) end
end

--- Is a prediction pending? nil key = any.
function PredictedEventChannel:has(key)
  if key == nil then return self._pending > 0 end
  return self._entries[key] ~= nil
end

function PredictedEventChannel:_settle_keys(key)
  if key ~= nil then return { key } end
  local keys = {}
  for k in pairs(self._entries) do table.insert(keys, k) end
  return keys
end

function PredictedEventChannel:_remove(key)
  local entry = self._entries[key]
  if entry == nil then return nil end
  self._entries[key] = nil
  self._pending = self._pending - 1
  return entry
end

--- The server agreed: settle the entry for `key` (nil = EVERY pending
--- entry). The entry is removed BEFORE on_confirm fires. Returns the count;
--- 0 fires on_unpredicted.
function PredictedEventChannel:confirm(key)
  local settled = 0
  for _, k in ipairs(self:_settle_keys(key)) do
    local entry = self:_remove(k)
    if entry ~= nil then
      if self._opts.on_confirm ~= nil then self._opts.on_confirm(entry.payload) end
      settled = settled + 1
    end
  end
  if settled == 0 and self._opts.on_unpredicted ~= nil then
    self._opts.on_unpredicted(key)
  end
  return settled
end

--- The server overruled: reject (nil key = every pending). Fires on_reject.
function PredictedEventChannel:reject(key)
  local rejected = 0
  for _, k in ipairs(self:_settle_keys(key)) do
    local entry = self:_remove(k)
    if entry ~= nil then
      if self._opts.on_reject ~= nil then self._opts.on_reject(entry.payload) end
      rejected = rejected + 1
    end
  end
  return rejected
end

--- Drop every pending entry SILENTLY (no callbacks).
function PredictedEventChannel:clear()
  self._entries = {}
  self._pending = 0
end

function PredictedEventChannel:tick(_now) end

--- Sim-born grace auto-rejects first, then wall-clock TTL (UI-born only —
--- sim-born entries settle by server progress, not wall time).
function PredictedEventChannel:prune()
  local grace = self._opts.grace_ticks or 10
  for key, entry in pairs(self._entries) do
    if entry.acked ~= nil and entry.acked() >= entry.seq + grace then
      self:_remove(key)
      if self._opts.on_reject ~= nil then self._opts.on_reject(entry.payload) end
    end
  end
  local rtt = (self._clock ~= nil) and self._clock:smoothed_rtt() or 0
  local ttl = self._opts.ttl_ms
  if ttl == nil or ttl <= 0 then ttl = math.max(rtt * 2, 600) end
  local now = self:_now()
  for key, entry in pairs(self._entries) do
    if entry.acked == nil and now - entry.at > ttl then
      self:_remove(key)
      if self._opts.on_reject ~= nil then self._opts.on_reject(entry.payload) end
    end
  end
end

--- Stop being driven and drop all entries (silently).
function PredictedEventChannel:dispose()
  self.dead = true
  self:clear()
end

return PredictedEventChannel
