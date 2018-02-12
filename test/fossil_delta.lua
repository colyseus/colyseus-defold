local fossil_delta = require 'colyseus.fossil_delta.fossil_delta'

function read_file(file)
    local f = assert(io.open(file, "rb"))
    local content = f:read("*all")
    f:close()
    return content
end

local function make_array_from_str(str)
  local arr = {}
  local i = 0

  while i < string.len(str) do
    arr[i + 1] = string.byte(str, i + 1)
    i = i + 1
  end

  return arr
end

local origin = make_array_from_str( read_file("test/data/1/origin") )
local target = make_array_from_str( read_file("test/data/1/target") )
local delta  = make_array_from_str( read_file("test/data/1/delta") )

local function to_string(arr)
  local str = ""
  for i,v in ipairs(arr) do
    str = str .. string.char(v)
  end
  return str
end

describe("colyseus", function()
  describe("fossil_delta", function()
    it("should expose 'create' and 'apply' methods", function()
      assert.truthy(fossil_delta.create)
      assert.truthy(fossil_delta.apply)
    end)

    it("should create delta", function()
      local delta_created = fossil_delta.create(origin, target)

      print("delta: " .. to_string(delta))
      print("delta created: " .. to_string(delta_created))
      -- assert.are.same(delta_created, delta)

      -- -- deep check comparisons!
      -- assert.are.same({ table = "great"}, { table = "great" })
      --
      -- -- or check by reference!
      -- assert.are_not.equal({ table = "great"}, { table = "great"})
      --
      -- assert.truthy("this is a string") -- truthy: not false or nil
      --
      -- assert.True(1 == 1)
      -- assert.is_true(1 == 1)
      --
      -- assert.falsy(nil)
      -- assert.has_error(function() error("Wat") end, "Wat")
    end)

    it("should provide some shortcuts to common functions", function()
      assert.are.unique({{ thing = 1 }, { thing = 2 }, { thing = 3 }})
    end)

  end)
end)

