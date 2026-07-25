--
-- Predicted-spawn store (port of the JS SDK's predict/predictedSpawns.ts):
-- optimistic locals live OUTSIDE the schema collection, correlated to the
-- authoritative entity on its add (fifo or predicate) and collapsed onto one
-- logical entry with a STABLE id — the handoff is invisible to sprites keyed
-- on entry.id.
--
-- Entry shape: { id, server, local_state, confirmed, lead_ms, at, accepted }
-- (`local_state` = the app's predicted local; `local` is a Lua keyword.)
--
local RoomClock = require 'colyseus.room_clock'

local PredictedSpawns = {}
PredictedSpawns.__index = PredictedSpawns

---@param opts table {owned = fun(server) -> bool, correlate = fun(local_state, server) -> bool,
---  spawn_time = fun(server) -> ms, step = fun(local_state, dt_seconds),
---  ttl = fun(rtt) -> ms (default max(2*rtt, 600)), on_reject = fun(local_state, id)}
---@param clock table|nil RoomClock (serverNow axis — same axis the lead lives on)
function PredictedSpawns.new(opts, clock)
  local self = setmetatable({}, PredictedSpawns)
  self._opts = opts or {}
  self._clock = clock
  self._by_id = {}       -- id -> entry
  self._by_server = {}   -- server instance -> entry
  self._order = {}       -- insertion order = FIFO order
  self._next_id = 1
  self._last_tick_at = nil
  self._size = 0
  self.dead = false
  self._on_disposed = nil
  return self
end

function PredictedSpawns:_now()
  if self._clock ~= nil then return self._clock:server_now() end
  return RoomClock.get_now()
end

function PredictedSpawns:size()
  return self._size
end

--- Record an optimistic local spawn; returns the entry (stable id).
function PredictedSpawns:spawn(local_state)
  local entry = {
    id = self._next_id,
    local_state = local_state,
    confirmed = false,
    lead_ms = 0,
    at = self:_now(),
    accepted = false,
  }
  self._next_id = self._next_id + 1
  self._by_id[entry.id] = entry
  table.insert(self._order, entry)
  self._size = self._size + 1
  return entry
end

--- Drop a still-pending prediction (no-op once confirmed).
function PredictedSpawns:cancel(id)
  local entry = self._by_id[id]
  if entry ~= nil and not entry.confirmed then self:_drop(entry) end
end

--- Exempt a still-pending entry from TTL eviction.
function PredictedSpawns:accept(id)
  local entry = self._by_id[id]
  if entry ~= nil then entry.accepted = true end
end

function PredictedSpawns:_drop(entry)
  self._by_id[entry.id] = nil
  if entry.server ~= nil then self._by_server[entry.server] = nil end
  for i, e in ipairs(self._order) do
    if e == entry then
      table.remove(self._order, i)
      break
    end
  end
  self._size = self._size - 1
end

--- Route the collection's on_add here.
function PredictedSpawns:handle_add(server)
  if server == nil or self._by_server[server] ~= nil then return end

  local owned = self._opts.owned == nil or self._opts.owned(server)
  local matched = nil
  if owned then
    for _, entry in ipairs(self._order) do
      if not entry.confirmed and entry.local_state ~= nil then
        if self._opts.correlate == nil
          or self._opts.correlate(entry.local_state, server) then
          matched = entry
          break
        end
      end
    end
  end

  if matched ~= nil then
    -- transition IN PLACE — same id, the handoff contract
    matched.server = server
    matched.confirmed = true
    if self._opts.spawn_time ~= nil and matched.at ~= nil then
      matched.lead_ms = self._opts.spawn_time(server) - matched.at
    end
    self._by_server[server] = matched
  else
    local entry = {
      id = self._next_id,
      server = server,
      confirmed = true,
      lead_ms = 0,
      accepted = false,
    }
    self._next_id = self._next_id + 1
    self._by_id[entry.id] = entry
    table.insert(self._order, entry)
    self._size = self._size + 1
    self._by_server[server] = entry
  end
end

--- Route the collection's on_remove here.
function PredictedSpawns:handle_remove(server)
  if server == nil then return end
  local entry = self._by_server[server]
  if entry ~= nil then self:_drop(entry) end
end

--- Advance pending locals on the serverNow axis (the same axis the lead
--- lives on — the handoff cannot jump).
function PredictedSpawns:tick(now)
  local t = (self._clock ~= nil) and self._clock:server_now() or now
  if self._opts.step ~= nil and self._last_tick_at ~= nil then
    local dt = math.max(0, (t - self._last_tick_at) / 1000)
    if dt > 0 then
      for _, entry in ipairs(self._order) do
        if not entry.confirmed and entry.local_state ~= nil then
          self._opts.step(entry.local_state, dt)
        end
      end
    end
  end
  self._last_tick_at = t
end

--- Drop pending locals older than the TTL — mispredicts.
function PredictedSpawns:prune()
  if self._size == 0 then return end
  local now = self:_now()
  local rtt = (self._clock ~= nil) and self._clock:smoothed_rtt() or 0
  local ttl = (self._opts.ttl ~= nil) and self._opts.ttl(rtt) or math.max(rtt * 2, 600)
  -- collect first — _drop mutates _order
  local evict = nil
  for _, entry in ipairs(self._order) do
    if not entry.confirmed and not entry.accepted and entry.at ~= nil
      and now - entry.at > ttl then
      evict = evict or {}
      table.insert(evict, entry)
    end
  end
  if evict == nil then return end
  for _, entry in ipairs(evict) do
    self:_drop(entry)
    if self._opts.on_reject ~= nil then
      self._opts.on_reject(entry.local_state, entry.id)
    end
  end
end

--- Iterate the merged view — exactly one entry per logical entity.
function PredictedSpawns:entries()
  return self._order
end

function PredictedSpawns:entry_for(server)
  if server == nil then return nil end
  return self._by_server[server]
end

function PredictedSpawns:alive(id)
  return self._by_id[id] ~= nil
end

--- Drop all predictions and tracked entries.
function PredictedSpawns:clear()
  self._by_id = {}
  self._by_server = {}
  self._order = {}
  self._size = 0
end

function PredictedSpawns:dispose()
  self.dead = true
  if self._on_disposed ~= nil then self._on_disposed() end
  self:clear()
end

return PredictedSpawns
