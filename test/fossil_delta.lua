local fossil_delta = require 'colyseus.serialization.fossil_delta.fossil_delta'

return function()
  function read_file(file)
      local f = assert(io.open(file, "rb"))
      local content = f:read("*all")
      f:close()
      return content
  end

  function table.clone(orig)
      local orig_type = type(orig)
      local copy
      if orig_type == 'table' then
          copy = {}
          for orig_key, orig_value in pairs(orig) do
              copy[orig_key] = orig_value
          end
      else -- number, string, boolean, etc
          copy = orig
      end
      return copy
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

  local origin = {}
  local target = {}
  local delta = {}

  local i = 1
  while i <= 5 do
    origin[i] = make_array_from_str( read_file("test/data/" .. i .. "/origin") )
    target[i] = make_array_from_str( read_file("test/data/" .. i .. "/target") )
    delta[i] = make_array_from_str( read_file("test/data/" .. i .. "/delta") )
    i = i + 1
  end

  local function to_string(arr)
    local str = ""
    for i,v in ipairs(arr) do
      str = str .. string.char(v)
    end
    return str
  end

  describe("fossil delta", function()

    it("should expose 'create' and 'apply' methods", function()
      assert(fossil_delta.create)
      assert(fossil_delta.apply)
    end)

    it("should create delta", function()
      assert_same(fossil_delta.create(origin[1], target[1]), delta[1])
      assert_same(fossil_delta.create(origin[2], target[2]), delta[2])
      assert_same(fossil_delta.create(origin[3], target[3]), delta[3])
      assert_same(fossil_delta.create(origin[4], target[4]), delta[4])
      assert_same(fossil_delta.create(origin[5], target[5]), delta[5])
    end)

    it("should apply delta", function()
      assert_same(fossil_delta.apply(table.clone(origin[1]), delta[1]), target[1])
      assert_same(fossil_delta.apply(table.clone(origin[2]), delta[2]), target[2])
      assert_same(fossil_delta.apply(table.clone(origin[3]), delta[3]), target[3])
      assert_same(fossil_delta.apply(table.clone(origin[4]), delta[4]), target[4])
      assert_same(fossil_delta.apply(table.clone(origin[5]), delta[5]), target[5])
    end)

  end)
end
