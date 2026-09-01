--
-- t.quantized() codec — a bounded float encoded as a fixed-width unsigned
-- integer. Port of @colyseus/schema 5.0 `src/types/quantize.ts`; the math
-- must stay bit-identical to the reference:
--
--   * rounding is explicit `floor(x + 0.5)` — NOT a language-default round
--     (they disagree on the .5 case across languages)
--   * wrapping ranges are reduced in the FLOAT domain before the integer
--     step (no huge-double→int cast)
--   * the wrap top step folds via `% span`, not a bitmask (bits=32 would
--     overflow 32-bit integer math)
--   * NaN → q=0 (both modes); ±Inf → q=0 for wrap, natural clamp for clamp
--   * all math in float64 (Lua numbers)
--
local M = {}

local WIRE_BY_BITS = { [8] = "uint8", [16] = "uint16", [32] = "uint32" }

--- Validate options and precompute the wire codec + scale span.
--- `mode` accepts "clamp"/"wrap" or the wire's 0/1.
---@param opts { min: number, max: number, bits: number|nil, mode: string|number|nil }
function M.resolve(opts)
  local min, max = opts.min, opts.max
  assert(type(min) == "number" and type(max) == "number" and max > min,
    "quantized: require finite min < max")

  local bits = opts.bits or 16
  assert(WIRE_BY_BITS[bits] ~= nil, "quantized: bits must be 8, 16 or 32")

  local wrap = (opts.mode == 1 or opts.mode == "wrap")
  local steps = 2 ^ bits

  return {
    min = min,
    max = max,
    bits = bits,
    wrap = wrap,
    wire = WIRE_BY_BITS[bits],
    range = max - min,
    -- wrapping spreads 2^bits steps across [min,max) (top ≡ bottom);
    -- clamped maps the endpoints onto 0 and 2^bits-1 inclusive — one fewer
    -- on a range symmetric about zero so zero lands on a step too
    span = wrap and steps or ((min == -max) and (steps - 2) or (steps - 1)),
  }
end

--- Float → unsigned integer.
function M.quantize(desc, value)
  if desc.wrap then
    -- non-finite can't be range-reduced; pin to q=0 so both peers agree
    if value ~= value or value == math.huge or value == -math.huge then
      return 0
    end
    local range = desc.range
    -- float-domain range reduction → [0, range)
    local a = (value - desc.min) % range
    if a < 0 then a = a + range end
    return math.floor((a / range) * desc.span + 0.5) % desc.span
  end

  if value ~= value then return 0 end -- NaN → min (±Inf clamps naturally)
  local v = value
  if v < desc.min then v = desc.min elseif v > desc.max then v = desc.max end
  return math.floor(((v - desc.min) / desc.range) * desc.span + 0.5)
end

--- Unsigned integer → float.
function M.dequantize(desc, q)
  return desc.min + (q / desc.span) * desc.range
end

--- Wire-exact round-trip — what a quantized field yields after assignment.
function M.snap(desc, value)
  return M.dequantize(desc, M.quantize(desc, value))
end

return M
