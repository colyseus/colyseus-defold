local schema = require 'colyseus.serialization.schema.schema'
local schema_serializer = require 'colyseus.serialization.schema'
local reference_tracker = require 'colyseus.serialization.schema.reference_tracker'

return function()
  local PrimitiveTypes = require 'test.schema.PrimitiveTypes.PrimitiveTypes'
  local ChildSchemaTypes = require 'test.schema.ChildSchemaTypes.ChildSchemaTypes'
  local ArraySchemaTypes = require 'test.schema.ArraySchemaTypes.ArraySchemaTypes'
  local MapSchemaTypes = require 'test.schema.MapSchemaTypes.MapSchemaTypes'
  local MapSchemaInt8 = require 'test.schema.MapSchemaInt8.MapSchemaInt8'
  local StateV1 = require 'test.schema.BackwardsForwards.StateV1'
  local StateV2 = require 'test.schema.BackwardsForwards.StateV2'
  local FilteredTypesState = require 'test.schema.FilteredTypes.State'
  local InstanceSharingTypes = require 'test.schema.InstanceSharingTypes.State'

  describe("schema serializer", function()

     describe("edge cases", function()
       local State = schema.define({
         ["fieldString"] = "string",
         ["_fields_by_index"] = { "fieldString" },
       });

       it("should decode complex UTF-8 characters", function()
         local bytes = {128, 190, 240, 159, 154, 128, 224, 165, 144, 230, 188, 162, 229, 173, 151, 226, 153, 164, 226, 153, 167, 226, 153, 165, 226, 153, 162, 194, 174, 226, 154, 148}

         local state = State:new()
         state:decode(bytes);

         assert_equal(state.fieldString, "🚀ॐ漢字♤♧♥♢®⚔")
       end)
     end)

     it("PrimitiveTypes", function()
       local bytes = { 128, 128, 129, 255, 130, 0, 128, 131, 255, 255, 132, 0, 0, 0, 128, 133, 255, 255, 255, 255, 134, 0, 0, 0, 0, 0, 0, 0, 128, 135, 255, 255, 255, 255, 255, 255, 31, 0, 136, 204, 204, 204, 253, 137, 255, 255, 255, 255, 255, 255, 239, 127, 138, 208, 128, 139, 204, 255, 140, 209, 0, 128, 141, 205, 255, 255, 142, 210, 0, 0, 0, 128, 143, 203, 0, 0, 224, 255, 255, 255, 239, 65, 144, 203, 0, 0, 0, 0, 0, 0, 224, 195, 145, 203, 255, 255, 255, 255, 255, 255, 63, 67, 146, 203, 61, 255, 145, 224, 255, 255, 239, 199, 147, 203, 153, 153, 153, 153, 153, 153, 185, 127, 148, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 149, 1 }

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
       assert_equal(tostring(state.float32), tostring(-3.4028234663853E37));
       assert_equal(tostring(state.float64), tostring(1.7976931348623E308));

       assert_equal(state.varint_int8, -128);
       assert_equal(state.varint_uint8, 255);
       assert_equal(state.varint_int16, -32768);
       assert_equal(state.varint_uint16, 65535);
       assert_equal(state.varint_int32, -2147483648);
       assert_equal(state.varint_uint32, 4294967295);
       assert_equal(state.varint_int64, -9223372036854775808);
       assert_equal(state.varint_uint64, 9007199254740991);
       assert_equal(tostring(state.varint_float32), tostring(-3.40282347E38));
       assert_equal(tostring(state.varint_float64), tostring(1.7976931348623E307));

       assert_equal(state.str, "Hello world");
       assert_equal(state.boolean, true);

     end)

     it("ChildSchema", function()
       local bytes = { 128, 1, 129, 2, 255, 1, 128, 205, 244, 1, 129, 205, 32, 3, 255, 2, 128, 204, 200, 129, 205, 44, 1 }

       local state = ChildSchemaTypes:new()
       state:decode(bytes)

       assert_equal(state.child.x, 500);
       assert_equal(state.child.y, 800);

       assert_equal(state.secondChild.x, 200);
       assert_equal(state.secondChild.y, 300);
     end)

    it("ArraySchemaTypes", function()
      local bytes = { 128, 1, 129, 2, 130, 3, 131, 4, 255, 1, 128, 0, 5, 128, 1, 6, 255, 2, 128, 0, 0, 128, 1, 10, 128, 2, 20, 128, 3, 205, 192, 13, 255, 3, 128, 0, 163, 111, 110, 101, 128, 1, 163, 116, 119, 111, 128, 2, 165, 116, 104, 114, 101, 101, 255, 4, 128, 0, 232, 3, 0, 0, 128, 1, 192, 13, 0, 0, 128, 2, 72, 244, 255, 255, 255, 5, 128, 100, 129, 208, 156, 255, 6, 128, 100, 129, 208, 156 }

      local state = ArraySchemaTypes:new()
      -- state.arrayOfSchemas.OnAdd += (value, key) => Debug.Log("onAdd, arrayOfSchemas => " + key);
      -- state.arrayOfNumbers.OnAdd += (value, key) => Debug.Log("onAdd, arrayOfNumbers => " + key);
      -- state.arrayOfStrings.OnAdd += (value, key) => Debug.Log("onAdd, arrayOfStrings => " + key);
      -- state.arrayOfInt32.OnAdd += (value, key) => Debug.Log("onAdd, arrayOfInt32 => " + key);

      local refs = reference_tracker:new()
      state:decode(bytes, nil, refs)

      assert_equal(#state.arrayOfSchemas.items, 2);
      assert_equal(state.arrayOfSchemas[1].x, 100);
      assert_equal(state.arrayOfSchemas[1].y, -100);
      assert_equal(state.arrayOfSchemas[2].x, 100);
      assert_equal(state.arrayOfSchemas[2].y, -100);

      assert_equal(#state.arrayOfNumbers.items, 4);
      assert_equal(state.arrayOfNumbers[1], 0);
      assert_equal(state.arrayOfNumbers[2], 10);
      assert_equal(state.arrayOfNumbers[3], 20);
      assert_equal(state.arrayOfNumbers[4], 3520);

      assert_equal(#state.arrayOfStrings.items, 3);
      assert_equal(state.arrayOfStrings[1], "one");
      assert_equal(state.arrayOfStrings[2], "two");
      assert_equal(state.arrayOfStrings[3], "three");

      assert_equal(#state.arrayOfInt32.items, 3);
      assert_equal(state.arrayOfInt32[1], 1000);
      assert_equal(state.arrayOfInt32[2], 3520);
      assert_equal(state.arrayOfInt32[3], -3000);

      -- -- state.arrayOfSchemas.OnRemove += (value, key) => Debug.Log("onRemove, arrayOfSchemas => " + key);
      -- -- state.arrayOfNumbers.OnRemove += (value, key) => Debug.Log("onRemove, arrayOfNumbers => " + key);
      -- -- state.arrayOfStrings.OnRemove += (value, key) => Debug.Log("onRemove, arrayOfStrings => " + key);
      -- -- state.arrayOfInt32.OnRemove += (value, key) => Debug.Log("onRemove, arrayOfInt32 => " + key);
      local pop_bytes = { 255, 1, 64, 1, 255, 2, 64, 3, 64, 2, 64, 1, 255, 4, 64, 2, 64, 1, 255, 3, 64, 2, 64, 1  }
      state:decode(pop_bytes, nil, refs)

      assert_equal(#state.arrayOfSchemas.items, 1);
      assert_equal(#state.arrayOfNumbers.items, 1);
      assert_equal(#state.arrayOfStrings.items, 1);
      assert_equal(#state.arrayOfInt32.items, 1);
    end)

    it("MapSchemaTypes", function()
      local bytes = { 128, 1, 129, 2, 130, 3, 131, 4, 255, 1, 128, 0, 163, 111, 110, 101, 5, 128, 1, 163, 116, 119, 111, 6, 128, 2, 165, 116, 104, 114, 101, 101, 7, 255, 2, 128, 0, 163, 111, 110, 101, 1, 128, 1, 163, 116, 119, 111, 2, 128, 2, 165, 116, 104, 114, 101, 101, 205, 192, 13, 255, 3, 128, 0, 163, 111, 110, 101, 163, 79, 110, 101, 128, 1, 163, 116, 119, 111, 163, 84, 119, 111, 128, 2, 165, 116, 104, 114, 101, 101, 165, 84, 104, 114, 101, 101, 255, 4, 128, 0, 163, 111, 110, 101, 192, 13, 0, 0, 128, 1, 163, 116, 119, 111, 24, 252, 255, 255, 128, 2, 165, 116, 104, 114, 101, 101, 208, 7, 0, 0, 255, 5, 128, 100, 129, 204, 200, 255, 6, 128, 205, 44, 1, 129, 205, 144, 1, 255, 7, 128, 205, 244, 1, 129, 205, 88, 2 }

      local state = MapSchemaTypes:new()

      --
      -- TODO: schema-codegen should auto-initialize MapSchema on constructor
      --
      state.mapOfSchemas['on_add'] = function (value, key) print("OnAdd, mapOfSchemas => " .. key, value) end;
      state.mapOfNumbers['on_add'] = function (value, key) print("OnAdd, mapOfNumbers => " .. key, value) end;
      state.mapOfStrings['on_add'] = function (value, key) print("OnAdd, mapOfStrings => " .. key, value) end;
      state.mapOfInt32['on_add'] = function (value, key) print("OnAdd, mapOfInt32 => " .. key, value) end;

      state.mapOfSchemas['on_remove'] = function (value, key) print("OnRemove, mapOfSchemas => " .. key, value) end;
      state.mapOfNumbers['on_remove'] = function (value, key) print("OnRemove, mapOfNumbers => " .. key, value) end;
      state.mapOfStrings['on_remove'] = function (value, key) print("OnRemove, mapOfStrings => " .. key, value) end;
      state.mapOfInt32['on_remove'] = function (value, key) print("OnRemove, mapOfInt32 => " .. key, value) end;

      local refs = reference_tracker:new()
      state:decode(bytes, nil, refs)

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

      local delete_bytes = {255, 2, 64, 1, 64, 2, 255, 1, 64, 1, 64, 2, 255, 3, 64, 1, 64, 2, 255, 4, 64, 1, 64, 2}
      state:decode(delete_bytes, nil, refs)

      assert_equal(state.mapOfSchemas:length(), 1);
      assert_equal(state.mapOfNumbers:length(), 1);
      assert_equal(state.mapOfStrings:length(), 1);
      assert_equal(state.mapOfInt32:length(), 1);
    end)

    it("MapSchemaInt8", function()
      local bytes = { 128, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 129, 1, 255, 1, 128, 0, 163, 98, 98, 98, 1, 128, 1, 163, 97, 97, 97, 1, 128, 2, 163, 50, 50, 49, 1, 128, 3, 163, 48, 50, 49, 1, 128, 4, 162, 49, 53, 1, 128, 5, 162, 49, 48, 1 }

      local state = MapSchemaInt8:new()

      local refs = reference_tracker:new()
      state:decode(bytes, nil, refs)

      assert_equal(state.status, "Hello world");
      assert_equal(state.mapOfInt8["bbb"], 1);
      assert_equal(state.mapOfInt8["aaa"], 1);
      assert_equal(state.mapOfInt8["221"], 1);
      assert_equal(state.mapOfInt8["021"], 1);
      assert_equal(state.mapOfInt8["15"], 1);
      assert_equal(state.mapOfInt8["10"], 1);

      local add_bytes = { 255, 1, 0, 5, 2 };
      state:decode(add_bytes, nil, refs);

      assert_equal(state.mapOfInt8["bbb"], 1);
      assert_equal(state.mapOfInt8["aaa"], 1);
      assert_equal(state.mapOfInt8["221"], 1);
      assert_equal(state.mapOfInt8["021"], 1);
      assert_equal(state.mapOfInt8["15"], 1);
      assert_equal(state.mapOfInt8["10"], 2);
    end)

    it("InheritedTypesTest", function()
      local serializer = schema_serializer.new()

      local handshake = { 128, 1, 129, 3, 255, 1, 128, 0, 2, 128, 1, 3, 128, 2, 4, 128, 3, 5, 255, 2, 129, 6, 128, 0, 255, 3, 129, 7, 128, 1, 255, 4, 129, 8, 128, 2, 255, 5, 129, 9, 128, 3, 255, 6, 128, 0, 10, 128, 1, 11, 255, 7, 128, 0, 12, 128, 1, 13, 128, 2, 14, 255, 8, 128, 0, 15, 128, 1, 16, 128, 2, 17, 128, 3, 18, 255, 9, 128, 0, 19, 128, 1, 20, 128, 2, 21, 128, 3, 22, 255, 10, 128, 161, 120, 129, 166, 110, 117, 109, 98, 101, 114, 255, 11, 128, 161, 121, 129, 166, 110, 117, 109, 98, 101, 114, 255, 12, 128, 161, 120, 129, 166, 110, 117, 109, 98, 101, 114, 255, 13, 128, 161, 121, 129, 166, 110, 117, 109, 98, 101, 114, 255, 14, 128, 164, 110, 97, 109, 101, 129, 166, 115, 116, 114, 105, 110, 103, 255, 15, 128, 161, 120, 129, 166, 110, 117, 109, 98, 101, 114, 255, 16, 128, 161, 121, 129, 166, 110, 117, 109, 98, 101, 114, 255, 17, 128, 164, 110, 97, 109, 101, 129, 166, 115, 116, 114, 105, 110, 103, 255, 18, 128, 165, 112, 111, 119, 101, 114, 129, 166, 110, 117, 109, 98, 101, 114, 255, 19, 128, 166, 101, 110, 116, 105, 116, 121, 130, 0, 129, 163, 114, 101, 102, 255, 20, 128, 166, 112, 108, 97, 121, 101, 114, 130, 1, 129, 163, 114, 101, 102, 255, 21, 128, 163, 98, 111, 116, 130, 2, 129, 163, 114, 101, 102, 255, 22, 128, 163, 97, 110, 121, 130, 0, 129, 163, 114, 101, 102 }
      serializer:handshake(handshake, { offset = 1 });

      local bytes = { 128, 1, 129, 2, 130, 3, 131, 4, 213, 2, 255, 1, 128, 205, 244, 1, 129, 205, 32, 3, 255, 2, 128, 204, 200, 129, 205, 44, 1, 130, 166, 80, 108, 97, 121, 101, 114, 255, 3, 128, 100, 129, 204, 150, 130, 163, 66, 111, 116, 131, 204, 200, 255, 4, 131, 100 }
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
      local statev1bytes = { 129, 1, 128, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 255, 1, 128, 0, 163, 111, 110, 101, 2, 255, 2, 128, 203, 232, 229, 22, 37, 231, 231, 209, 63, 129, 203, 240, 138, 15, 5, 219, 40, 223, 63 }
      local statev2bytes = { 128, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 130, 10 }

      local statev2 = StateV2:new()
      statev2:decode(statev1bytes)
      assert_equal(statev2.str, "Hello world")

      local statev1 =  StateV1:new()
      statev1:decode(statev2bytes);
      assert_equal(statev1.str, "Hello world");
    end)

    it("FilteredTypesTest", function()
      local client1 = FilteredTypesState:new()
      client1:decode({ 255, 0, 130, 1, 128, 2, 128, 2, 255, 1, 128, 0, 4, 255, 2, 128, 163, 111, 110, 101, 255, 2, 128, 163, 111, 110, 101, 255, 4, 128, 163, 111, 110, 101 })
      assert_equal("one", client1.playerOne.name);
      assert_equal("one", client1.players[1].name);
      assert_equal(nil, client1.playerTwo.name);

      local client2 =  FilteredTypesState:new()
      client2:decode({ 255, 0, 130, 1, 129, 3, 129, 3, 255, 1, 128, 1, 5, 255, 3, 128, 163, 116, 119, 111, 255, 3, 128, 163, 116, 119, 111, 255, 5, 128, 163, 116, 119, 111 })
      assert_equal("two", client2.playerTwo.name);
      assert_equal("two", client2.players[1].name);
      -- assert_equal("two", client2.players[1].name);
      assert_equal(nil, client2.playerOne.name);
    end)

    it("InstanceSharingTypes", function()
      local refs = reference_tracker:new()
      local client = InstanceSharingTypes:new()

      client:decode({ 130, 1, 131, 2, 128, 3, 129, 3, 255, 1, 255, 2, 255, 3, 128, 4, 255, 3, 128, 4, 255, 4, 128, 10, 129, 10, 255, 4, 128, 10, 129, 10 }, nil, refs);
      assert_equal(client.player1, client.player2);
      assert_equal(client.player1.position, client.player2.position);
      assert_equal(refs.ref_counts[client.player1.__refid], 2);
      assert_equal(5, refs:count());

      client:decode({ 130, 1, 131, 2, 64, 65 }, nil, refs);
      assert_equal(nil, client.player1);
      assert_equal(nil, client.player2);
      assert_equal(3, refs:count());

      client:decode({ 255, 1, 128, 0, 5, 128, 1, 5, 128, 2, 5, 128, 3, 6, 255, 5, 128, 7, 255, 6, 128, 8, 255, 7, 128, 10, 129, 10, 255, 8, 128, 10, 129, 10 }, nil, refs);
      assert_equal(client.arrayOfPlayers[1], client.arrayOfPlayers[2]);
      assert_equal(client.arrayOfPlayers[2], client.arrayOfPlayers[3]);
      assert_not_equal(client.arrayOfPlayers[3], client.arrayOfPlayers[4]);
      assert_equal(7, refs:count());

      client:decode({ 255, 1, 64, 3, 64, 2, 64, 1 }, nil, refs);
      assert_equal(1, client.arrayOfPlayers:length());
      assert_equal(5, refs:count());
      local previous_array_schema__refid = client.arrayOfPlayers.__refid;

      -- Replacing ArraySchema
      client:decode({ 130, 9, 255, 9, 128, 0, 10, 255, 10, 128, 11, 255, 11, 128, 10, 129, 20 }, nil, refs);
      assert_equal(false, refs:has(previous_array_schema__refid));
      assert_equal(1, client.arrayOfPlayers:length());
      assert_equal(5, refs:count());

      -- Clearing ArraySchema
      client:decode({ 255, 9, 10 }, nil, refs);
      assert_equal(0, client.arrayOfPlayers:length());
      assert_equal(3, refs:count());
    end)

  end)
end
