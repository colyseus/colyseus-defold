--
-- Shared rollback engine (port of the JS SDK's predict/rollback.ts) — the
-- base of Reconciler. A pure OBSERVER of an InputHandle: you mutate + send
-- through the handle; the controller steps each send eagerly (on_send hook),
-- polls the server ack in tick() and rewinds-to-truth + replays on new acks,
-- absorbing mispredictions into per-field visual offsets that decay.
--
-- Subclass hooks (override on the derived class):
--   _smoothed_fields() -> list   _read_current(f)     _adopt_truth()
--   _apply_step(cmd)             _snapshot_prev()     _reseed_state()
--   _truth_matches_at(acked) [false]  _refresh_render() [no-op]
--   _mark_dirty() [no-op]
--
local Drift = require 'colyseus.predict.drift'

---@class StepContext
---@field dt number fixed step in SECONDS
---@field dt_ms number fixed step in MILLISECONDS
---@field tick number the input's seq — the index of the step being simulated
---@field sub_steps number physics sub-steps per fixed step (>= 1)
---@field is_replay boolean true while re-simulating during rollback
---@field reckon_time number the input's lag-comp instant (server-clock ms)
local StepContext = {}
StepContext.__index = StepContext

--- Memoize a VALUE on the rollback timeline that replay can't re-derive:
--- computed ONCE on the live step for this seq, frozen, and returned WITHOUT
--- re-running on every replay. `memo(compute)` uses the shared key-less slot;
--- `memo(key, compute)` disambiguates multiple memos per step.
function StepContext:memo(key_or_compute, compute)
  local key = key_or_compute
  if compute == nil then
    key = ""
    compute = key_or_compute
  end
  return self._owner:_memo_run(key, self.is_replay, self.tick, compute)
end

--- Declare an optimistic discrete EVENT the timeline just produced into an
--- event channel — fires only on the LIVE step (skipped on replay).
function StepContext:predict(sink, payload)
  if not self.is_replay then
    sink:_predict_from_sim(self.tick, payload, self._owner._ack_watermark)
  end
end

local RollbackController = {}
RollbackController.__index = RollbackController

---@param opts table {input, clock, smooth_ms, snap, step_ms, step_seconds, sub_steps, on_reconcile, warn_on_divergence}
function RollbackController.init(self, opts)
  local input = opts.input
  assert(input ~= nil, "RollbackController: input handle required")
  self._input = input
  self._clock = opts.clock

  -- error-decay time constant (ms); 0 = hard snap. Default: the server's
  -- correction cadence (one patch interval) so a correction fades before the
  -- next one lands — else 50.
  local smooth_ms = opts.smooth_ms
  if smooth_ms == nil then
    smooth_ms = (input.patch_rate ~= nil and input.patch_rate > 0)
      and input.patch_rate or 50
  end
  self._smooth_ms = smooth_ms
  self._snap_threshold = opts.snap or 0

  local step_ms = opts.step_ms or input.step_ms
    or (opts.step_seconds ~= nil and opts.step_seconds * 1000 or nil)
  assert(step_ms ~= nil,
    "reconciler: fixed simulation step is unknown. The server room must call " ..
    "setFixedTimestep() (or setTimestep()), or pass step_ms/step_seconds " ..
    "explicitly — a wrong dt silently diverges rollback-replay.")
  self.step_ms = step_ms

  local dt = opts.step_seconds or input.step_seconds or (step_ms / 1000)
  local sub_steps = opts.sub_steps or input.sub_steps or 1
  if sub_steps < 1 then sub_steps = 1 end

  -- one mutable instance reused across steps — no per-step alloc
  self._ctx = setmetatable({
    dt = dt,
    dt_ms = step_ms,
    tick = 0,
    sub_steps = sub_steps,
    sub_dt = dt / sub_steps,
    sub_dt_ms = step_ms / sub_steps,
    is_replay = false,
    reckon_time = 0,
    lag_comp_active = false,
    _owner = self,
  }, StepContext)

  self._on_reconcile = opts.on_reconcile
  self._warn_tolerance = opts.warn_on_divergence
  self._ack_watermark = function() return input.last_processed end

  --- diagnostics: per-field correction from the most recent reconcile
  self.last_correction = {}
  self.last_correction_mag = 0
  self.reconcile_seq = 0
  self.drift = Drift.new()
  self.dead = false

  self._error = {}
  self._prev = {}
  self._rendered_before = {}
  self._memos = {}          -- seq -> { key -> value }
  self._last_tick = -1
  self._last_acked = input.last_processed
  self._last_epoch = input.epoch
  self._replay_from = 0
  self._predicted_seq = input.sent_count -- pre-existing sends are NOT predicted
  self._catching = false
  self._render_acc = 0
  self._disposed_hooks = {}

  self._unsubscribe_send = input:on_send(function() self:_catch_up() end)
end

--- Number of unacknowledged inputs currently buffered.
function RollbackController:pending_count()
  return self._input:pending_count()
end

--- Advance one render frame: follow the handle's epoch (self-reset), poll the
--- server ack (reconcile), decay the correction offsets. Live inputs are
--- stepped eagerly via the handle's on_send hook.
function RollbackController:tick(now)
  local dt = (self._last_tick < 0) and 0 or (now - self._last_tick)
  self._last_tick = now
  if dt > 0 and self.step_ms > 0 then
    self._render_acc = self._render_acc + dt
  end

  local epoch = self._input.epoch
  if epoch ~= self._last_epoch then
    self._last_epoch = epoch
    self:reset()
  end

  local acked = self._input.last_processed
  if acked > self._last_acked then
    self._last_acked = acked
    self:_reconcile(acked)
  end
  self:_mark_dirty()

  if dt <= 0 then return end
  local k = (self._smooth_ms <= 0) and 1 or (1 - math.exp(-dt / self._smooth_ms))
  local err = self._error
  for _, f in ipairs(self:_smoothed_fields()) do
    err[f] = (err[f] or 0) * (1 - k)
  end
end

--- Interpolation factor between the last two fixed steps (0..1).
function RollbackController:_render_alpha()
  if self.step_ms <= 0 then return 1 end
  local a = self._render_acc / self.step_ms
  if a < 0 then return 0 end
  if a > 1 then return 1 end
  return a
end

function RollbackController:_catch_up()
  local sent = self._input.sent_count
  if self._predicted_seq >= sent or self._catching then return end
  self._catching = true
  self._ctx.is_replay = false
  for seq = self._predicted_seq + 1, sent do
    local inp = self._input:at(seq)
    if inp ~= nil then
      self:_snapshot_prev()
      self:_run_step(seq, inp)
      self:_refresh_render()
      -- consume one step of render time per live step
      self._render_acc = self._render_acc - self.step_ms
      if self._render_acc < 0 then
        self._render_acc = 0
      elseif self._render_acc >= self.step_ms then
        self._render_acc = self._render_acc % self.step_ms
      end
    end
    self._predicted_seq = seq
  end
  self._catching = false
end

function RollbackController:_run_step(seq, command)
  local ctx = self._ctx
  ctx.tick = seq
  local raw = self._input:reckon_time_at(seq)
  ctx.lag_comp_active = raw > 0
  if raw > 0 then
    ctx.reckon_time = raw
  else
    ctx.reckon_time = (self._clock ~= nil) and self._clock:server_now() or 0
  end
  self:_apply_step(command)
end

function RollbackController:_reconcile(acked)
  local fields = self:_smoothed_fields()
  local err, prev = self._error, self._prev

  if self:_truth_matches_at(acked) then
    -- wire-precision match: keep own full-precision state, zero telemetry
    for _, f in ipairs(fields) do self.last_correction[f] = 0 end
    self.last_correction_mag = 0
    Drift.update(self.drift, 0)
    self.reconcile_seq = self.reconcile_seq + 1
    self:_memo_prune(acked)
    if self._on_reconcile ~= nil then self._on_reconcile(acked) end
    return
  end

  local before = self._rendered_before
  for _, f in ipairs(fields) do
    before[f] = self:_read_current(f) + (err[f] or 0)
  end

  self:_adopt_truth()

  local from = math.max(acked, self._replay_from)
  self._ctx.is_replay = true
  self._catching = true
  for seq = from + 1, self._input.sent_count do
    local inp = self._input:at(seq)
    if inp ~= nil then self:_run_step(seq, inp) end
  end
  self._catching = false
  self._ctx.is_replay = false
  self:_refresh_render()
  self._predicted_seq = self._input.sent_count

  -- error rebase: what the player SAW minus the corrected result
  local hard = self._smooth_ms <= 0
  local mag = 0
  for _, f in ipairs(fields) do
    local correction = before[f] - self:_read_current(f)
    err[f] = hard and 0 or correction
    local a = math.abs(correction)
    if a > mag then mag = a end
    self.last_correction[f] = correction
  end

  -- teleport-scale corrections POP all-or-nothing instead of gliding
  local popped = self._snap_threshold > 0 and mag > self._snap_threshold
  if popped then
    for _, f in ipairs(fields) do
      err[f] = 0
      prev[f] = self:_read_current(f)
    end
  end
  self.reconcile_seq = self.reconcile_seq + 1
  self.last_correction_mag = mag
  if not popped then
    Drift.update(self.drift, mag)
    if self._warn_tolerance ~= nil
      and Drift.classify(self.drift, self._warn_tolerance) == "diverging" then
      print("colyseus.predict: reconcile corrections are trending (ema " ..
        string.format("%.4f", self.drift.ema) .. ") — client/server step likely diverged")
    end
  end

  self:_memo_prune(acked)
  if self._on_reconcile ~= nil then self._on_reconcile(acked) end
end

function RollbackController:_memo_run(key, is_replay, tick, compute)
  if is_replay then
    local slot = self._memos[tick]
    return slot ~= nil and slot[key] or nil
  end
  local value = compute()
  if value ~= nil then
    local slot = self._memos[tick]
    if slot == nil then
      slot = {}
      self._memos[tick] = slot
    end
    slot[key] = value
  end
  return value
end

function RollbackController:_memo_prune(acked)
  for seq in pairs(self._memos) do
    if seq <= acked then self._memos[seq] = nil end
  end
end

--- Re-seed local state from the authoritative instance(s): clears the
--- offsets, memos, and the in-flight window. The controller self-resets on
--- the handle's epoch (reconnect).
function RollbackController:reset()
  self:_reseed_state()
  Drift.reset(self.drift)
  self._replay_from = self._input.sent_count
  self._predicted_seq = self._input.sent_count
  self._last_acked = self._input.last_processed
  self._render_acc = 0
  self._memos = {}
  self:_mark_dirty()
end

function RollbackController:on_disposed(hook)
  table.insert(self._disposed_hooks, hook)
end

function RollbackController:dispose()
  self.dead = true
  self._unsubscribe_send()
  local hooks = self._disposed_hooks
  self._disposed_hooks = {}
  for _, hook in ipairs(hooks) do hook() end
end

-- default subclass hooks
function RollbackController:_truth_matches_at(_acked) return false end
function RollbackController:_refresh_render() end
function RollbackController:_mark_dirty() end

return RollbackController
