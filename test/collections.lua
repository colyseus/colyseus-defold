--
-- Collection accessors, driven directly (decode round-trips live in
-- schema_serializer): MapSchema get/has for keys that shadow a method or an
-- internal field, and ArraySchema order + length across holes.
--
local MapSchema = require 'colyseus.serializer.schema.types.map_schema'
local ArraySchema = require 'colyseus.serializer.schema.types.array_schema'
local OPERATION = require('colyseus.serializer.schema.constants').OPERATION

local function walk(arr)
  local seen = {}
  arr:each(function(value, index) table.insert(seen, index .. "=" .. value) end)
  return table.concat(seen, ",")
end

return function()
  describe("MapSchema", function()
    it("get/has reach keys that shadow methods and fields", function()
      local map = MapSchema:new()
      for i, key in ipairs({ "keys", "items", "length", "get", "alice" }) do
        map:set_by_index(i - 1, key, key:upper())
      end

      assert_equal("KEYS", map:get("keys"))
      assert_equal("ITEMS", map:get("items"))
      assert_equal("LENGTH", map:get("length"))
      assert_equal("GET", map:get("get"))
      assert_equal(true, map:has("length"))
      assert_equal(false, map:has("bob"))
      assert_equal(5, map:length())

      -- indexing still reaches a key that doesn't collide...
      assert_equal("ALICE", map["alice"])
      -- ...but resolves the method for one that does
      assert_equal(MapSchema.keys, map["keys"])
    end)

    it("has() follows deletes", function()
      local map = MapSchema:new()
      map:set_by_index(0, "length", 1)
      map:delete_by_index(0)
      assert_equal(false, map:has("length"))
      assert_nil(map:get("length"))
      assert_equal(0, map:length())
    end)
  end)

  describe("ArraySchema", function()
    it("each/index_of walk in index order", function()
      local arr = ArraySchema:new()
      -- written back to front: the entries start in the hash part, which
      -- pairs() walks in no particular order
      arr[3] = "c"
      arr[2] = "b"
      arr[1] = "a"
      assert_equal("1=a,2=b,3=c", walk(arr))
      assert_equal(3, arr:length())
      assert_equal(2, arr:index_of("b"))
      assert_equal(-1, arr:index_of("z"))
    end)

    it("length/each skip holes until decode end compacts them", function()
      local arr = ArraySchema:new()
      for i, value in ipairs({ "a", "b", "c", "d" }) do
        arr:set_by_index(i, value, OPERATION.ADD)
      end
      assert_equal(4, arr:length())

      arr:delete_by_index(2)
      assert_equal(3, arr:length())
      assert_equal("1=a,3=c,4=d", walk(arr))
      assert_equal(3, arr:index_of("c"))

      arr:__on_decode_end()
      assert_equal(3, arr:length())
      assert_equal("1=a,2=c,3=d", walk(arr))
      assert_equal(2, arr:index_of("c"))
    end)

    it("insert-ADD and clone keep the order", function()
      local arr = ArraySchema:new()
      for i, value in ipairs({ "a", "b", "c" }) do
        arr:set_by_index(i, value, OPERATION.ADD)
      end
      arr:set_by_index(2, "x", OPERATION.ADD) -- occupied: shifts b, c up
      assert_equal(4, arr:length())
      assert_equal("1=a,2=x,3=b,4=c", walk(arr))

      arr:delete_by_index(1)
      local copy = arr:clone()
      assert_equal(3, copy:length())
      assert_equal("2=x,3=b,4=c", walk(copy))
    end)
  end)
end
