local bit = require 'colyseus.serializer.bit'

--
-- Encode counterpart of `decode.lua` for the wire primitives the room layer
-- emits (little-endian, msgpack-style). Port of @colyseus/schema
-- `src/encoding/encode.ts` — the dynamic "number" codec and the fixed-width
-- primitives the input layer needs. Pure Lua 5.1 (no string.pack / ffi).
--

local mfloor, mabs, mhuge, mfrexp = math.floor, math.abs, math.huge, math.frexp

local function uint8 (bytes, num)
  table.insert(bytes, bit.band(num, 255))
end

local function int8 (bytes, num)
  table.insert(bytes, bit.band(num, 255))
end

local function uint16(bytes, value)
  table.insert(bytes, bit.band(value, 255))
  table.insert(bytes, bit.band(bit.arshift(value, 8), 255))
end

local function int16(bytes, value)
  uint16(bytes, value)
end

local function uint32(bytes, value)
  -- value may exceed the 32-bit signed range of `bit` ops — split via math
  local low = value % 65536
  local high = mfloor(value / 65536) % 65536
  table.insert(bytes, low % 256)
  table.insert(bytes, mfloor(low / 256))
  table.insert(bytes, high % 256)
  table.insert(bytes, mfloor(high / 256))
end

local function int32(bytes, value)
  if value < 0 then value = value + 4294967296 end
  uint32(bytes, value)
end

local function int64(bytes, value)
  local high = mfloor(value / 4294967296)
  local low = value - high * 4294967296
  uint32(bytes, low)
  uint32(bytes, (high < 0) and (high + 4294967296) or high)
end

local function uint64(bytes, value)
  local high = mfloor(value / 4294967296)
  local low = value - high * 4294967296
  uint32(bytes, low)
  uint32(bytes, high)
end

--- Round `value` to the nearest float32 (the value an IEEE 754 single would
--- hold) — used by the number codec's precision check and by float32().
--- Returns the rounded value plus its (sign, expo, mant) fields.
local function float32_fields(value)
  local sign = 0
  if value < 0 then sign = 1; value = -value end

  if value ~= value then return 0 / 0, sign, 255, 4194304 end -- nan (quiet)
  if value == mhuge then return mhuge, sign, 255, 0 end
  if value == 0 then return 0, sign, 0, 0 end

  local mant, expo = mfrexp(value)  -- value = mant * 2^expo, mant in [0.5, 1)
  expo = expo + 126                 -- IEEE bias: e = expo - 1 + 127

  if expo >= 255 then
    return mhuge, sign, 255, 0      -- overflow → inf
  end

  local m
  if expo <= 0 then
    -- subnormal: mantissa scaled by the denormal exponent, no implicit bit
    m = mfloor(mant * 2 ^ (expo + 23) + 0.5)
    expo = 0
    if m >= 8388608 then expo = 1; m = 0 end -- rounding carried into normal range
  else
    m = mfloor((mant * 2 - 1) * 8388608 + 0.5) -- 2^23
    if m >= 8388608 then                        -- rounding carry
      m = 0
      expo = expo + 1
      if expo >= 255 then return mhuge, sign, 255, 0 end
    end
  end

  local rounded
  if expo == 0 then
    rounded = m * 2 ^ -149
  else
    rounded = (1 + m / 8388608) * 2 ^ (expo - 127)
  end
  return rounded, sign, expo, m
end

local function float32(bytes, value)
  local _, sign, expo, mant = float32_fields(value)
  table.insert(bytes, mant % 256)
  table.insert(bytes, mfloor(mant / 256) % 256)
  table.insert(bytes, mfloor(mant / 65536) + (expo % 2) * 128)
  table.insert(bytes, mfloor(expo / 2) + sign * 128)
end

local function float64(bytes, value)
  local sign = 0
  if value < 0 then sign = 1; value = -value end

  local expo, mant
  if value ~= value then
    expo, mant = 2047, 2251799813685248 -- quiet nan (0x8000000000000)
  elseif value == mhuge then
    expo, mant = 2047, 0
  elseif value == 0 then
    expo, mant = 0, 0
  else
    local m, e = mfrexp(value)
    expo = e + 1022
    if expo <= 0 then
      mant = mfloor(m * 2 ^ (expo + 52) + 0.5) -- subnormal
      expo = 0
    else
      mant = (m * 2 - 1) * 4503599627370496   -- 2^52 — exact for doubles
    end
  end

  local b7_mant = mfloor(mant / 281474976710656) -- high 4 mantissa bits
  local low48 = mant - b7_mant * 281474976710656
  table.insert(bytes, low48 % 256)
  table.insert(bytes, mfloor(low48 / 256) % 256)
  table.insert(bytes, mfloor(low48 / 65536) % 256)
  table.insert(bytes, mfloor(low48 / 16777216) % 256)
  table.insert(bytes, mfloor(low48 / 4294967296) % 256)
  table.insert(bytes, mfloor(low48 / 1099511627776) % 256)
  table.insert(bytes, b7_mant + (expo % 16) * 16)
  table.insert(bytes, mfloor(expo / 16) + sign * 128)
end

local function boolean(bytes, value)
  table.insert(bytes, value and 1 or 0)
end

local function utf8_length(str)
  local c = 0
  local length = 0

  local i = 1
  local strlen = #str
  while i <= strlen do
    c = str:byte(i)

    if c < 0x80 then
      length = length + 1

    elseif c < 0x800 then
      length = length + 2

    elseif c < 0xd800 or c >= 0xe000 then
      length = length + 3

    else
      i = i + 1
      length = length + 4
    end

    i = i + 1
  end

  return length
end

local function utf8_write(bytes, offset, str)
  local len = #str
  local c = 0
  local i = 1

  while i <= len do
    c = str:byte(i)

    if c < 0x80 then
      offset = offset + 1
      bytes[offset] = c

    elseif c < 0x800 then
      offset = offset + 1
      bytes[offset] = bit.bor(0xc0, bit.arshift(c, 6))

      offset = offset + 1
      bytes[offset] = bit.bor(0x80, bit.band(c, 0x3f))

    elseif c < 0xd800 or c >= 0xe000 then
      offset = offset + 1
      bytes[offset] = bit.bor(0xe0, bit.arshift(c, 12))

      offset = offset + 1
      bytes[offset] = bit.bor(0x80, bit.band(bit.arshift(c, 6), 0x3f))

      offset = offset + 1
      bytes[offset] = bit.bor(0x80, bit.band(c, 0x3f))

    else
      i = i + 1
      c = 0x10000 + bit.bor(bit.lshift(bit.band(c, 0x3ff), 10), bit.band(str:byte(i), 0x3ff))

      offset = offset + 1
      bytes[offset] = bit.bor(0xf0, bit.arshift(c, 18))

      offset = offset + 1
      bytes[offset] = bit.bor(0x80, bit.band(bit.arshift(c, 12), 0x3f))

      offset = offset + 1
      bytes[offset] = bit.bor(0x80, bit.band(bit.arshift(c, 6), 0x3f))

      offset = offset + 1
      bytes[offset] = bit.bor(0x80, bit.band(c, 0x3f))
    end

    i = i + 1
  end
end

local function encode_string(bytes, value)
  -- encode `null` strings as empty.
  if not value then value = "" end

  local length = utf8_length(value)
  local size = 0

  -- fixstr
  if length < 0x20 then
    table.insert(bytes, bit.bor(length, 0xa0))
    size = 1

  -- str 8
  elseif length < 0x100 then
    table.insert(bytes, 0xd9)
    uint8(bytes, length)
    size = 2

  -- str 16
  elseif length < 0x10000 then
    table.insert(bytes, 0xda)
    uint16(bytes, length)
    size = 3

  -- str 32
  elseif length < 0x100000000 then
    table.insert(bytes, 0xdb)
    uint32(bytes, length)
    size = 5

  else
    error('String too long')
  end

  utf8_write(bytes, #bytes, value)

  return size + length
end

local MAX_SAFE_INTEGER = 9007199254740991

--- The schema dynamic "number" codec (msgpack-style, both signs + floats).
--- NaN encodes as 0; ±Infinity as ±MAX_SAFE_INTEGER; fractional values as
--- float32 when the f32 round-trip stays within 1e-4, else float64.
local function encode_number(bytes, value)
  if value ~= value then -- nan
    return encode_number(bytes, 0)
  end
  if value == mhuge then
    return encode_number(bytes, MAX_SAFE_INTEGER)
  end
  if value == -mhuge then
    return encode_number(bytes, -MAX_SAFE_INTEGER)
  end

  -- JS `value !== (value|0)`: fractional OR outside int32 range → float branch
  local is_int32 = (value == mfloor(value)) and value >= -2147483648 and value <= 2147483647
  if not is_int32 then
    if mabs(value) <= 3.4028235e+38 then
      local as_f32 = float32_fields(value)
      -- precision check — 1e-4 acceptable loss (mirrors the reference)
      if mabs(mabs(as_f32) - mabs(value)) < 1e-4 then
        table.insert(bytes, 0xca)
        float32(bytes, value)
        return
      end
    end
    table.insert(bytes, 0xcb)
    float64(bytes, value)
    return
  end

  if value >= 0 then
    if value < 0x80 then
      table.insert(bytes, value)
    elseif value < 0x100 then
      table.insert(bytes, 0xcc)
      table.insert(bytes, value)
    elseif value < 0x10000 then
      table.insert(bytes, 0xcd)
      uint16(bytes, value)
    else
      table.insert(bytes, 0xce)
      uint32(bytes, value)
    end
  else
    if value >= -0x20 then
      table.insert(bytes, bit.bor(0xe0, value + 0x20))
    elseif value >= -0x80 then
      table.insert(bytes, 0xd0)
      int8(bytes, value)
    elseif value >= -0x8000 then
      table.insert(bytes, 0xd1)
      int16(bytes, value)
    else
      table.insert(bytes, 0xd2)
      int32(bytes, value)
    end
  end
end

return {
  string = encode_string,
  number = encode_number,
  boolean = boolean,
  int8 = int8,
  uint8 = uint8,
  int16 = int16,
  uint16 = uint16,
  int32 = int32,
  uint32 = uint32,
  int64 = int64,
  uint64 = uint64,
  float32 = float32,
  float64 = float64,
  fround = float32_fields, -- (value) -> nearest-f32 value (+ sign, expo, mant)
}
