--
-- Reconcile-drift telemetry (port of the JS SDK's predict/drift.ts).
-- Fed one |correction| magnitude per reconcile; `ema` tracks the trend,
-- `peak` decays 10%/reconcile so isolated spikes read as jitter.
--
local M = {}

function M.new()
  return { ema = 0, peak = 0 }
end

function M.update(drift, mag)
  drift.ema = drift.ema + (mag - drift.ema) * 0.1
  drift.peak = math.max(mag, drift.peak * 0.9)
end

--- "matched" | "jitter" (spiky but not trending) | "diverging" (trending).
function M.classify(drift, tolerance)
  local floor = (tolerance ~= nil and tolerance > 1e-3) and tolerance or 1e-3
  if drift.ema >= floor then return "diverging" end
  if drift.peak >= floor then return "jitter" end
  return "matched"
end

function M.reset(drift)
  drift.ema = 0
  drift.peak = 0
end

return M
