--
-- Per-room clock-sync + RTT estimator, fed by the TIMED prefix the server
-- prepends to state messages when the room declared input via defineInput().
-- Port of the JS SDK's RoomClock.ts (RoomClockImpl) — pure math.
--
-- Two independent estimates:
--   * clock offset (server_now()): seeded by the first sample, then
--     EMA-smoothed; updates gated to low-jitter packets (RTT within 1.2× the
--     10s windowed-minimum RTT), except during a 30-sample post-reset warmup.
--   * RTT (rtt()/smoothed_rtt()): fed by the input ack round-trip; seeded by
--     the first valid sample; outliers (> 4× smoothed) rejected.
--
-- A room that never declares input never receives TIMED samples: the clock
-- then reports server_now() == now() and zeros.
--
local RoomClock = {}
RoomClock.__index = RoomClock

--- Injectable monotonic ms clock (tests replace this).
function RoomClock.get_now()
  return socket.gettime() * 1000
end

local EMA_ALPHA = 0.1
local RENDER_TAU = 250
local RENDER_SNAP = 250
local RTT_OUTLIER_X = 4
local JITTER_GAIN = 1 / 16
local JITTER_STALL_X = 4
local RTT_GATE_FACTOR = 1.2
local RTT_GATE_WINDOW = 10000
local RTT_GATE_WARMUP = 30

function RoomClock.new()
  local self = setmetatable({}, RoomClock)
  self._clock_offset = 0
  self._clock_has_sample = false
  self._offset_count = 0
  self._rtt_floor_t = {}
  self._rtt_floor_v = {}
  self._rtt = 0
  self._smoothed_rtt = 0
  self._rtt_has_sample = false
  self._jitter = 0
  self._last_recv_time = -1
  self._last_server_time = 0
  self._patch_interval = 0
  self._render_tau = RENDER_TAU
  self._render_sn = 0
  self._render_sn_at = 0
  return self
end

--- Local monotonic clock (ms) — the un-offset base server_now() builds on.
function RoomClock:now()
  return RoomClock.get_now()
end

--- Estimated server clock: ms since room start (reconstructed via the wire
--- sNow + local offset). Returns the local clock until the first sample.
function RoomClock:server_now()
  return RoomClock.get_now() + self._clock_offset
end

--- Server clock on a SLEW-LIMITED render timeline: free-runs at 1 ms/ms and
--- servos toward server_now() (tau ~250ms), snapping past gaps > 250ms. Use
--- for DRAWING remote entities; never for server-stamped deadlines.
function RoomClock:render_now()
  local target = self:server_now()
  if self._render_tau <= 0 then return target end
  local t = RoomClock.get_now()
  if self._render_sn == 0 then
    self._render_sn = target
    self._render_sn_at = t
    return self._render_sn
  end
  local dt = math.min(t - self._render_sn_at, 100) -- clamp tab-resume stalls
  if dt < 0.5 then return self._render_sn end      -- same frame — advance once
  self._render_sn_at = t
  self._render_sn = self._render_sn + dt           -- free-run at 1 ms/ms
  if math.abs(target - self._render_sn) > RENDER_SNAP then
    self._render_sn = target
    return self._render_sn
  end
  self._render_sn = self._render_sn + (target - self._render_sn) * (1 - math.exp(-dt / self._render_tau))
  return self._render_sn
end

--- Set the render_now slew time-constant (ms); <= 0 disables slewing.
function RoomClock:set_render_tau(milliseconds)
  self._render_tau = (milliseconds > 0) and milliseconds or 0
end

--- Most recent RTT sample (ms); 0 until the first valid sample.
function RoomClock:rtt()
  return self._rtt
end

--- EMA-smoothed RTT (ms); prefer for forward-prediction.
function RoomClock:smoothed_rtt()
  return self._smoothed_rtt
end

--- RFC 3550-style interarrival jitter (ms) vs the advertised patch cadence.
function RoomClock:jitter()
  return self._jitter
end

--- Raw sNow of the last TIMED sample — the snapshot's server-encode time.
function RoomClock:last_server_time()
  return self._last_server_time
end

--- Server snapshot cadence (patchRate, ms); 0 until advertised.
function RoomClock:patch_interval()
  return self._patch_interval
end

--- Feed the advertised patch cadence (ms) from the input handshake.
function RoomClock:set_patch_interval(milliseconds)
  self._patch_interval = (milliseconds > 0) and milliseconds or 0
end

--- Feed a decoded TIMED sample: sNow (ms since room start) updates the clock
--- offset; rtt_sample (ms round-trip from the input ack, < 0 if none this
--- packet) updates the RTT estimate.
function RoomClock:sample(s_now, rtt_sample)
  local t_now = RoomClock.get_now()
  local a = EMA_ALPHA

  -- jitter vs the cadence — idle patches round to a whole multiple; bursts
  -- (mult 0) and stalls (mult > 4) are skipped
  local pi = self._patch_interval
  if self._last_recv_time >= 0 and pi > 0 then
    local gap = t_now - self._last_recv_time
    local mult = math.floor(gap / pi + 0.5)
    if mult >= 1 and mult <= JITTER_STALL_X then
      self._jitter = self._jitter + (math.abs(gap - mult * pi) - self._jitter) * JITTER_GAIN
    end
  end
  self._last_recv_time = t_now

  self._last_server_time = s_now

  -- reject impossible / outlier RTT (tab-resume spikes once converged)
  if rtt_sample < 0 then
    rtt_sample = -1
  elseif self._smoothed_rtt > 0 and rtt_sample > self._smoothed_rtt * RTT_OUTLIER_X then
    rtt_sample = -1
  end

  -- offset: prefer the RTT-corrected estimate when a fresh sample exists
  local offset_sample = (rtt_sample >= 0) and (s_now + rtt_sample / 2 - t_now) or (s_now - t_now)
  if not self._clock_has_sample then
    self._clock_offset = offset_sample
    self._clock_has_sample = true
    if rtt_sample >= 0 then
      self:_push_rtt_floor(rtt_sample, t_now)
      self._offset_count = 1
    end
  elseif rtt_sample >= 0 then
    -- gate on the windowed-min RTT floor — except during post-reset warmup
    local floor_rtt = self:_push_rtt_floor(rtt_sample, t_now)
    local warming = self._offset_count < RTT_GATE_WARMUP
    self._offset_count = self._offset_count + 1
    if warming or rtt_sample <= floor_rtt * RTT_GATE_FACTOR then
      self._clock_offset = self._clock_offset * (1 - a) + offset_sample * a
    end
  end

  -- RTT: seeded on the first valid sample (separate flag from the offset seed)
  if rtt_sample >= 0 then
    self._rtt = rtt_sample
    if not self._rtt_has_sample then
      self._smoothed_rtt = rtt_sample
      self._rtt_has_sample = true
    else
      self._smoothed_rtt = self._smoothed_rtt * (1 - a) + rtt_sample * a
    end
  end
end

--- Push an RTT sample into the sliding-window-min deque; returns the floor.
function RoomClock:_push_rtt_floor(rtt_sample, t_now)
  local T, V = self._rtt_floor_t, self._rtt_floor_v
  while #V > 0 and V[#V] >= rtt_sample do
    table.remove(V)
    table.remove(T)
  end
  table.insert(V, rtt_sample)
  table.insert(T, t_now)
  local cutoff = t_now - RTT_GATE_WINDOW
  while #T > 0 and T[1] < cutoff do
    table.remove(T, 1)
    table.remove(V, 1)
  end
  return V[1]
end

--- Reset all state (reconnect). tau and patch_interval are config — they survive.
function RoomClock:reset()
  self._clock_offset = 0
  self._clock_has_sample = false
  self._offset_count = 0
  self._rtt = 0
  self._smoothed_rtt = 0
  self._rtt_has_sample = false
  self._jitter = 0
  self._last_recv_time = -1
  self._last_server_time = 0
  self._rtt_floor_t = {}
  self._rtt_floor_v = {}
  self._render_sn = 0
  self._render_sn_at = 0
end

return RoomClock
