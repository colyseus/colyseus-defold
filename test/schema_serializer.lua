local schema = require 'colyseus.serialization.schema.schema'
local schema_serializer = require 'colyseus.serialization.schema'

return function()
  local PrimitiveTypes = require 'test.schema.PrimitiveTypes.PrimitiveTypes'
  local ChildSchemaTypes = require 'test.schema.ChildSchemaTypes.ChildSchemaTypes'
  local ArraySchemaTypes = require 'test.schema.ArraySchemaTypes.ArraySchemaTypes'
  local MapSchemaTypes = require 'test.schema.MapSchemaTypes.MapSchemaTypes'
  local MapSchemaInt8 = require 'test.schema.MapSchemaInt8.MapSchemaInt8'
  local StateV1 = require 'test.schema.BackwardsForwards.StateV1'
  local StateV2 = require 'test.schema.BackwardsForwards.StateV2'

  describe("schema serializer", function()

    describe("edge cases", function()
      local State = schema.define({
        ["fieldString"] = "string",
        ["_order"] = { "fieldString" },
      });

      it("should decode complex UTF-8 characters", function()
        local bytes = { 0, 166, 208, 179, 209, 133, 208, 177 }

        local state = State:new()
        state:decode(bytes);

        assert_equal(state.fieldString, "гхб")
      end)
    end)

    it("PrimitiveTypes", function()
      local bytes = { 0, 128, 1, 255, 2, 0, 128, 3, 255, 255, 4, 0, 0, 0, 128, 5, 255, 255, 255, 255, 6, 0, 0, 0, 0, 0, 0, 0, 128, 7, 255, 255, 255, 255, 255, 255, 31, 0, 8, 0, 0, 128, 255, 9, 255, 255, 255, 255, 255, 255, 239, 127, 10, 208, 128, 11, 204, 255, 12, 209, 0, 128, 13, 205, 255, 255, 14, 210, 0, 0, 0, 128, 15, 203, 0, 0, 224, 255, 255, 255, 239, 65, 16, 203, 0, 0, 0, 0, 0, 0, 224, 195, 17, 203, 255, 255, 255, 255, 255, 255, 63, 67, 18, 203, 61, 255, 145, 224, 255, 255, 239, 199, 19, 203, 255, 255, 255, 255, 255, 255, 239, 127, 20, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 21, 1 }

      local state = PrimitiveTypes:new()
      state:decode(bytes)

      assert_equal(state.int8, -128);
      assert_equal(state.uint8, 255);
      assert_equal(state.int16, -32768);
      assert_equal(state.uint16, 65535);
      assert_equal(state.int32, -2147483648);
      assert_equal(state.uint32, 4294967295);
      assert_equal(state.int64, -9223372036854775808);
      assert_equal(state.uint64, 9007199254740991);
      assert_equal(state.float32, -math.huge); -- This doesn't look right!
      assert_equal(state.float64, 1.7976931348623157e+308);

      assert_equal(state.varint_int8, -128);
      assert_equal(state.varint_uint8, 255);
      assert_equal(state.varint_int16, -32768);
      assert_equal(state.varint_uint16, 65535);
      assert_equal(state.varint_int32, -2147483648);
      assert_equal(state.varint_uint32, 4294967295);
      assert_equal(state.varint_int64, -9223372036854775808);
      assert_equal(state.varint_uint64, 9007199254740991);
      assert_equal(state.varint_float32, -3.40282347e+38);
      assert_equal(tostring(state.varint_float64), tostring(1.7976931348623e+308)); -- why need to cast to string for them to be the same here?

      assert_equal(state.str, "Hello world");
      assert_equal(state.boolean, true);

    end)

    it("ChildSchema", function()
      local bytes = { 0, 0, 205, 244, 1, 1, 205, 32, 3, 193, 1, 0, 204, 200, 1, 205, 44, 1, 193 }

      local state = ChildSchemaTypes:new()
      state:decode(bytes)

      assert_equal(state.child.x, 500);
      assert_equal(state.child.y, 800);

      assert_equal(state.secondChild.x, 200);
      assert_equal(state.secondChild.y, 300);
    end)

    it("ArraySchemaTypes", function()
      local bytes = { 0, 2, 2, 0, 0, 100, 1, 208, 156, 193, 1, 0, 100, 1, 208, 156, 193, 1, 4, 4, 0, 0, 1, 10, 2, 20, 3, 205, 192, 13, 2, 3, 3, 0, 163, 111, 110, 101, 1, 163, 116, 119, 111, 2, 165, 116, 104, 114, 101, 101, 3, 3, 3, 0, 232, 3, 0, 0, 1, 192, 13, 0, 0, 2, 72, 244, 255, 255 }

      local state = ArraySchemaTypes:new()
      -- state.arrayOfSchemas.OnAdd += (value, key) => Debug.Log("onAdd, arrayOfSchemas => " + key);
      -- state.arrayOfNumbers.OnAdd += (value, key) => Debug.Log("onAdd, arrayOfNumbers => " + key);
      -- state.arrayOfStrings.OnAdd += (value, key) => Debug.Log("onAdd, arrayOfStrings => " + key);
      -- state.arrayOfInt32.OnAdd += (value, key) => Debug.Log("onAdd, arrayOfInt32 => " + key);

      state:decode(bytes)

      assert_equal(#state.arrayOfSchemas, 2);
      assert_equal(state.arrayOfSchemas[1].x, 100);
      assert_equal(state.arrayOfSchemas[1].y, -100);
      assert_equal(state.arrayOfSchemas[2].x, 100);
      assert_equal(state.arrayOfSchemas[2].y, -100);

      assert_equal(#state.arrayOfNumbers, 4);
      assert_equal(state.arrayOfNumbers[1], 0);
      assert_equal(state.arrayOfNumbers[2], 10);
      assert_equal(state.arrayOfNumbers[3], 20);
      assert_equal(state.arrayOfNumbers[4], 3520);

      assert_equal(#state.arrayOfStrings, 3);
      assert_equal(state.arrayOfStrings[1], "one");
      assert_equal(state.arrayOfStrings[2], "two");
      assert_equal(state.arrayOfStrings[3], "three");

      assert_equal(#state.arrayOfInt32, 3);
      assert_equal(state.arrayOfInt32[1], 1000);
      assert_equal(state.arrayOfInt32[2], 3520);
      assert_equal(state.arrayOfInt32[3], -3000);

      -- -- state.arrayOfSchemas.OnRemove += (value, key) => Debug.Log("onRemove, arrayOfSchemas => " + key);
      -- -- state.arrayOfNumbers.OnRemove += (value, key) => Debug.Log("onRemove, arrayOfNumbers => " + key);
      -- -- state.arrayOfStrings.OnRemove += (value, key) => Debug.Log("onRemove, arrayOfStrings => " + key);
      -- -- state.arrayOfInt32.OnRemove += (value, key) => Debug.Log("onRemove, arrayOfInt32 => " + key);
      local pop_bytes = { 0, 1, 0, 1, 1, 0, 3, 1, 0, 2, 1, 0 }
      state:decode(pop_bytes)

      assert_equal(#state.arrayOfSchemas, 1);
      assert_equal(#state.arrayOfNumbers, 1);
      assert_equal(#state.arrayOfStrings, 1);
      assert_equal(#state.arrayOfInt32, 1);
    end)

    it("MapSchemaTypes", function()
      local bytes = { 0, 3, 163, 111, 110, 101, 0, 100, 1, 204, 200, 193, 163, 116, 119, 111, 0, 205, 44, 1, 1, 205, 144, 1, 193, 165, 116, 104, 114, 101, 101, 0, 205, 244, 1, 1, 205, 88, 2, 193, 1, 3, 163, 111, 110, 101, 1, 163, 116, 119, 111, 2, 165, 116, 104, 114, 101, 101, 205, 192, 13, 2, 3, 163, 111, 110, 101, 163, 79, 110, 101, 163, 116, 119, 111, 163, 84, 119, 111, 165, 116, 104, 114, 101, 101, 165, 84, 104, 114, 101, 101, 3, 3, 163, 111, 110, 101, 192, 13, 0, 0, 163, 116, 119, 111, 24, 252, 255, 255, 165, 116, 104, 114, 101, 101, 208, 7, 0, 0 }

      local state = MapSchemaTypes:new()

      --
      -- TODO: schema-codegen should auto-initialize MapSchema on constructor
      --
      -- state.mapOfSchemas['on_add'] = function (value, key) print("OnAdd, mapOfSchemas => " .. key) end;
      -- state.mapOfNumbers['on_add'] = function (value, key) print("OnAdd, mapOfNumbers => " .. key) end;
      -- state.mapOfStrings['on_add'] = function (value, key) print("OnAdd, mapOfStrings => " .. key) end;
      -- state.mapOfInt32['on_add'] = function (value, key) print("OnAdd, mapOfInt32 => " .. key) end;
      --
      -- state.mapOfSchemas['on_remove'] = function (value, key) print("OnRemove, mapOfSchemas => " .. key) end;
      -- state.mapOfNumbers['on_remove'] = function (value, key) print("OnRemove, mapOfNumbers => " .. key) end;
      -- state.mapOfStrings['on_remove'] = function (value, key) print("OnRemove, mapOfStrings => " .. key) end;
      -- state.mapOfInt32['on_remove'] = function (value, key) print("OnRemove, mapOfInt32 => " .. key) end;

      state:decode(bytes)

      assert_equal(state.mapOfSchemas:length(), 3);
      assert_equal(state.mapOfSchemas["one"].x, 100);
      assert_equal(state.mapOfSchemas["one"].y, 200);
      assert_equal(state.mapOfSchemas["two"].x, 300);
      assert_equal(state.mapOfSchemas["two"].y, 400);
      assert_equal(state.mapOfSchemas["three"].x, 500);
      assert_equal(state.mapOfSchemas["three"].y, 600);

      assert_equal(state.mapOfNumbers:length(), 3);
      assert_equal(state.mapOfNumbers["one"], 1);
      assert_equal(state.mapOfNumbers["two"], 2);
      assert_equal(state.mapOfNumbers["three"], 3520);

      assert_equal(state.mapOfStrings:length(), 3);
      assert_equal(state.mapOfStrings["one"], "One");
      assert_equal(state.mapOfStrings["two"], "Two");
      assert_equal(state.mapOfStrings["three"], "Three");

      assert_equal(state.mapOfInt32:length(), 3);
      assert_equal(state.mapOfInt32["one"], 3520);
      assert_equal(state.mapOfInt32["two"], -1000);
      assert_equal(state.mapOfInt32["three"], 2000);

      local delete_bytes = { 1, 2, 192, 1, 192, 2, 0, 2, 192, 1, 192, 2, 2, 2, 192, 1, 192, 2, 3, 2, 192, 1, 192, 2 }
      state:decode(delete_bytes)

      assert_equal(state.mapOfSchemas:length(), 1);
      assert_equal(state.mapOfNumbers:length(), 1);
      assert_equal(state.mapOfStrings:length(), 1);
      assert_equal(state.mapOfInt32:length(), 1);
    end)

    it("MapSchemaInt8", function()
      local bytes = { 0, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 1, 6, 163, 98, 98, 98, 1, 163, 97, 97, 97, 1, 163, 50, 50, 49, 1, 163, 48, 50, 49, 1, 162, 49, 53, 1, 162, 49, 48, 1 }

      local state = MapSchemaInt8:new()
      state:decode(bytes)

      assert_equal(state.status, "Hello world");
      assert_equal(state.mapOfInt8["bbb"], 1);
      assert_equal(state.mapOfInt8["aaa"], 1);
      assert_equal(state.mapOfInt8["221"], 1);
      assert_equal(state.mapOfInt8["021"], 1);
      assert_equal(state.mapOfInt8["15"], 1);
      assert_equal(state.mapOfInt8["10"], 1);

      local add_bytes = { 1, 1, 5, 2 };
      state:decode(add_bytes);

      assert_equal(state.mapOfInt8["bbb"], 1);
      assert_equal(state.mapOfInt8["aaa"], 1);
      assert_equal(state.mapOfInt8["221"], 1);
      assert_equal(state.mapOfInt8["021"], 1);
      assert_equal(state.mapOfInt8["15"], 1);
      assert_equal(state.mapOfInt8["10"], 2);
    end)

    it("InheritedTypesTest", function()
      local serializer = schema_serializer.new()

      local handshake = { 0, 4, 4, 0, 0, 0, 1, 2, 2, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 193, 1, 0, 1, 1, 3, 3, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 2, 0, 164, 110, 97, 109, 101, 1, 166, 115, 116, 114, 105, 110, 103, 193, 193, 2, 0, 2, 1, 4, 4, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 2, 0, 164, 110, 97, 109, 101, 1, 166, 115, 116, 114, 105, 110, 103, 193, 3, 0, 165, 112, 111, 119, 101, 114, 1, 166, 110, 117, 109, 98, 101, 114, 193, 193, 3, 0, 3, 1, 4, 4, 0, 0, 166, 101, 110, 116, 105, 116, 121, 1, 163, 114, 101, 102, 2, 0, 193, 1, 0, 166, 112, 108, 97, 121, 101, 114, 1, 163, 114, 101, 102, 2, 1, 193, 2, 0, 163, 98, 111, 116, 1, 163, 114, 101, 102, 2, 2, 193, 3, 0, 163, 97, 110, 121, 1, 163, 114, 101, 102, 2, 0, 193, 193, 1, 3 }
      serializer:handshake(handshake, { offset = 1 });

      local bytes = { 0, 0, 205, 244, 1, 1, 205, 32, 3, 193, 1, 0, 204, 200, 1, 205, 44, 1, 2, 166, 80, 108, 97, 121, 101, 114, 193, 2, 0, 100, 1, 204, 150, 2, 163, 66, 111, 116, 3, 204, 200, 193, 3, 213, 2, 3, 100, 193 }
      serializer:set_state(bytes, { offset = 1 })

      local state = serializer:get_state()

      -- Assert.IsInstanceOf(typeof(SchemaTest.InheritedTypes.Entity), state.entity);
      assert_equal(state.entity.x, 500);
      assert_equal(state.entity.y, 800);

      -- Assert.IsInstanceOf(typeof(SchemaTest.InheritedTypes.Player), state.player);
      assert_equal(state.player.x, 200);
      assert_equal(state.player.y, 300);
      assert_equal(state.player.name, "Player");

      -- Assert.IsInstanceOf(typeof(SchemaTest.InheritedTypes.Bot), state.bot);
      assert_equal(state.bot.x, 100);
      assert_equal(state.bot.y, 150);
      assert_equal(state.bot.name, "Bot");
      assert_equal(state.bot.power, 200);

      -- Assert.IsInstanceOf(typeof(SchemaTest.InheritedTypes.Bot), state.any);
    end)

    it("BackwardsForwardsTest", function()
      local statev1bytes = { 1, 1, 163, 111, 110, 101, 0, 203, 64, 45, 212, 207, 108, 69, 148, 63, 1, 203, 120, 56, 150, 252, 58, 73, 224, 63, 193, 0, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100 }
      local statev2bytes = { 0, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 2, 10 }

      local statev2 = StateV2:new()
      statev2:decode(statev1bytes)
      assert_equal(statev2.str, "Hello world")

      local statev1 =  StateV1:new()
      statev1:decode(statev2bytes);
      assert_equal(statev1.str, "Hello world");
    end)

  end)
end
