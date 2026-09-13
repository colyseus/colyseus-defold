--
-- Number encoding edges: MessagePack floats (the message payload codec) and
-- the schema float32 rounding used by input encoding. Reference values from
-- node: Buffer.write{Double,Float}BE and Math.fround.
--
local msgpack = require 'colyseus.messagepack.MessagePack'
local encode = require 'colyseus.serializer.schema.encoding.encode'

local function hex(s)
  return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function unhex(h)
  return (h:gsub("%x%x", function(b) return string.char(tonumber(b, 16)) end))
end

local function pack_float(n)
  local buffer = {}
  msgpack.packers['float'](buffer, n)
  return table.concat(buffer)
end

-- value, big-endian IEEE bits
local DOUBLES = {
  { 5e-324, "0000000000000001" },                  -- smallest subnormal
  { -5e-324, "8000000000000001" },
  { 1e-310, "000012688b70e62b" },
  { 2.225073858507201e-308, "000fffffffffffff" },  -- largest subnormal
  { 2.2250738585072014e-308, "0010000000000000" }, -- smallest normal
  { 1.5, "3ff8000000000000" },
}

-- value, big-endian IEEE bits, the float32 those bits hold
local FLOATS = {
  { 1.401298464324817e-45, "00000001", 1.401298464324817e-45 },
  { -1.401298464324817e-45, "80000001", -1.401298464324817e-45 },
  { 1e-40, "000116c2", 9.99994610111476e-41 },
  { 1.1754942106924411e-38, "007fffff", 1.1754942106924411e-38 },
  { 1.1754943508222875e-38, "00800000", 1.1754943508222875e-38 },
  { 0.1, "3dcccccd", 0.10000000149011612 },           -- rounds, doesn't truncate
  { -2.5, "c0200000", -2.5 },
  { 3.4028235677973362e38, "7f7fffff", 3.4028234663852886e38 },
  { 3.4028235677973366e38, "7f800000", math.huge },   -- halfway past max: to inf
}

-- value, Math.fround(value)
local FROUND = {
  { -1.5, -1.5 },
  { -0.1, -0.10000000149011612 },
  { 16777217, 16777216 },      -- tie: to even (down)
  { -16777217, -16777216 },
  { 16777219, 16777220 },      -- tie: to even (up)
  { 33554433, 33554432 },
  { -33554435, -33554436 },
  { 1e-45, 1.401298464324817e-45 },
  { -1e-45, -1.401298464324817e-45 },
  { 5.877471754111438e-39, 5.877471754111438e-39 },
  { 3.4028235e38, 3.4028234663852886e38 },
  { -3.4028236e38, -math.huge },
}

return function()
  describe("MessagePack floats", function()
    it("packs and unpacks doubles, subnormals included", function()
      for _, case in ipairs(DOUBLES) do
        local value, bits = case[1], case[2]
        assert_equal("cb" .. bits, hex(msgpack.pack(value)))
        assert_equal(value, msgpack.unpack(unhex("cb" .. bits)))
      end
    end)

    it("packs and unpacks floats, subnormals included", function()
      for _, case in ipairs(FLOATS) do
        local value, bits, stored = case[1], case[2], case[3]
        assert_equal("ca" .. bits, hex(pack_float(value)))
        assert_equal(stored, msgpack.unpack(unhex("ca" .. bits)))
      end
    end)
  end)

  describe("schema float32", function()
    it("fround matches Math.fround", function()
      for _, case in ipairs(FROUND) do
        assert_equal(case[2], (encode.fround(case[1])))
      end
    end)

    it("float32 writes the tie-to-even bits", function()
      local bytes = {}
      encode.float32(bytes, -16777217)
      -- 0xcb800000 (-16777216), little-endian
      assert_equal("0,0,128,203", table.concat(bytes, ","))
    end)
  end)
end
