local schema = require 'colyseus.serializer.schema.schema'
local Decoder = require 'colyseus.serializer.schema.decoder'
local schema_serializer = require 'colyseus.serializer.schema_serializer'
local get_callbacks = require 'colyseus.serializer.schema.callbacks'

return function()
  local PrimitiveTypes = require 'test.schema.PrimitiveTypes.PrimitiveTypes'
  local ChildSchemaTypes = require 'test.schema.ChildSchemaTypes.ChildSchemaTypes'
  local ArraySchemaTypes = require 'test.schema.ArraySchemaTypes.ArraySchemaTypes'
  local MapSchemaTypes = require 'test.schema.MapSchemaTypes.MapSchemaTypes'
  local MapSchemaInt8 = require 'test.schema.MapSchemaInt8.MapSchemaInt8'
  local StateV1 = require 'test.schema.BackwardsForwards.StateV1'
  local StateV2 = require 'test.schema.BackwardsForwards.StateV2'
  local InstanceSharingTypes = require 'test.schema.InstanceSharingTypes.State'
  local CallbacksState = require 'test.schema.Callbacks.CallbacksState'

  describe("schema serializer", function()

    describe("edge cases", function()
      local State = schema.define({
        ["fieldString"] = "string",
        ["_fields_by_index"] = { "fieldString" },
      });

      it("should decode complex UTF-8 characters", function()
        local bytes = { 128, 190, 240, 159, 154, 128, 224, 165, 144, 230, 188, 162, 229, 173, 151, 226, 153, 164, 226, 153, 167, 226, 153, 165, 226, 153, 162, 194, 174, 226, 154, 148 }

        local state = State:new()
        local decoder = Decoder:new(state)
        decoder:decode(bytes);

        assert_equal(state.fieldString, "🚀ॐ漢字♤♧♥♢®⚔")
      end)
    end)

    it("PrimitiveTypes", function()
      local bytes = { 128, 128, 129, 255, 130, 0, 128, 131, 255, 255, 132, 0, 0, 0, 128, 133, 255, 255, 255, 255, 134, 0, 0, 0, 0, 0, 0, 0, 128, 135, 255, 255, 255, 255, 255, 255, 31, 0, 136, 204, 204, 204, 253, 137, 255, 255, 255, 255, 255, 255, 239, 127, 138, 208, 128, 139, 204, 255, 140, 209, 0, 128, 141, 205, 255, 255, 142, 210, 0, 0, 0, 128, 143, 203, 0, 0, 224, 255, 255, 255, 239, 65, 144, 203, 0, 0, 0, 0, 0, 0, 224, 195, 145, 203, 255, 255, 255, 255, 255, 255, 63, 67, 146, 203, 61, 255, 145, 224, 255, 255, 239, 199, 147, 203, 153, 153, 153, 153, 153, 153, 185, 127, 148, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 149, 1 }

      local state = PrimitiveTypes:new()
      local decoder = Decoder:new(state)
      local callbacks = get_callbacks(decoder)
      decoder:decode(bytes)

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

      local immediate_listen_count = 0
      callbacks:listen("int8", function(value)
        immediate_listen_count = immediate_listen_count + 1
      end)
      assert_equal(1, immediate_listen_count);

      state:to_raw()  -- to_raw() should not throw any errors
    end)

    it("ChildSchema", function()
      local bytes = { 128, 1, 129, 2, 255, 1, 128, 205, 244, 1, 129, 205, 32, 3, 255, 2, 128, 204, 200, 129, 205, 44, 1 }

      local state = ChildSchemaTypes:new()
      local decoder = Decoder:new(state)
      decoder:decode(bytes)

      assert_equal(state.child.x, 500);
      assert_equal(state.child.y, 800);

      assert_equal(state.secondChild.x, 200);
      assert_equal(state.secondChild.y, 300);

      state:to_raw()  -- to_raw() should not throw any errors
    end)

    it("ArraySchemaTypes", function()
      local bytes = { 128, 1, 129, 2, 130, 3, 131, 4, 255, 1, 128, 0, 5, 128, 1, 6, 255, 2, 128, 0, 0, 128, 1, 10, 128, 2, 20, 128, 3, 205, 192, 13, 255, 3, 128, 0, 163, 111, 110, 101, 128, 1, 163, 116, 119, 111, 128, 2, 165, 116, 104, 114, 101, 101, 255, 4, 128, 0, 232, 3, 0, 0, 128, 1, 192, 13, 0, 0, 128, 2, 72, 244, 255, 255, 255, 5, 128, 100, 129, 208, 156, 255, 6, 128, 100, 129, 208, 156 }

      local state = ArraySchemaTypes:new()
      local decoder = Decoder:new(state)

      local callbacks = get_callbacks(decoder)

      local arrayOfSchemasOnAdd = 0
      local arrayOfNumbersOnAdd = 0
      local arrayOfStringsOnAdd = 0
      local arrayOfInt32OnAdd = 0
      callbacks:on_add("arrayOfSchemas", function(value, key) arrayOfSchemasOnAdd = arrayOfSchemasOnAdd + 1 end)
      callbacks:on_add("arrayOfNumbers", function(value, key) arrayOfNumbersOnAdd = arrayOfNumbersOnAdd + 1 end)
      callbacks:on_add("arrayOfStrings", function(value, key) arrayOfStringsOnAdd = arrayOfStringsOnAdd + 1 end)
      callbacks:on_add("arrayOfInt32", function(value, key) arrayOfInt32OnAdd = arrayOfInt32OnAdd + 1 end)

      local arrayOfSchemasOnRemove = 0
      local arrayOfNumbersOnRemove = 0
      local arrayOfStringsOnRemove = 0
      local arrayOfInt32OnRemove = 0
      callbacks:on_remove("arrayOfSchemas", function(value, key) arrayOfSchemasOnRemove = arrayOfSchemasOnRemove + 1 end)
      callbacks:on_remove("arrayOfNumbers", function(value, key) arrayOfNumbersOnRemove = arrayOfNumbersOnRemove + 1 end)
      callbacks:on_remove("arrayOfStrings", function(value, key) arrayOfStringsOnRemove = arrayOfStringsOnRemove + 1 end)
      callbacks:on_remove("arrayOfInt32", function(value, key) arrayOfInt32OnRemove = arrayOfInt32OnRemove + 1 end)

      decoder:decode(bytes)

      assert_equal(arrayOfSchemasOnAdd, 2);
      assert_equal(arrayOfNumbersOnAdd, 4);
      assert_equal(arrayOfStringsOnAdd, 3);
      assert_equal(arrayOfInt32OnAdd, 3);

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

      local pop_bytes = { 255, 1, 64, 1, 255, 2, 64, 3, 64, 2, 64, 1, 255, 4, 64, 2, 64, 1, 255, 3, 64, 2, 64, 1 }
      decoder:decode(pop_bytes)

      assert_equal(#state.arrayOfSchemas.items, 1);
      assert_equal(#state.arrayOfNumbers.items, 1);
      assert_equal(#state.arrayOfStrings.items, 1);
      assert_equal(#state.arrayOfInt32.items, 1);

      assert_equal(arrayOfSchemasOnRemove, 1);
      assert_equal(arrayOfNumbersOnRemove, 3);
      assert_equal(arrayOfStringsOnRemove, 2);
      assert_equal(arrayOfInt32OnRemove, 2);

      state:to_raw() -- to_raw() should not throw any errors

      local reassign_bytes = { 128, 7, 129, 8, 131, 9, 130, 10, 255, 7, 255, 8, 255, 9, 255, 10 }
      decoder:decode(reassign_bytes)

      assert_equal(#state.arrayOfSchemas.items, 0);
      assert_equal(#state.arrayOfNumbers.items, 0);
      assert_equal(#state.arrayOfStrings.items, 0);
      assert_equal(#state.arrayOfInt32.items, 0);
    end)

    it("MapSchemaTypes", function()
      local bytes = { 128, 1, 129, 2, 130, 3, 131, 4, 255, 1, 128, 0, 163, 111, 110, 101, 5, 128, 1, 163, 116, 119, 111, 6, 128, 2, 165, 116, 104, 114, 101, 101, 7, 255, 2, 128, 0, 163, 111, 110, 101, 1, 128, 1, 163, 116, 119, 111, 2, 128, 2, 165, 116, 104, 114, 101, 101, 205, 192, 13, 255, 3, 128, 0, 163, 111, 110, 101, 163, 79, 110, 101, 128, 1, 163, 116, 119, 111, 163, 84, 119, 111, 128, 2, 165, 116, 104, 114, 101, 101, 165, 84, 104, 114, 101, 101, 255, 4, 128, 0, 163, 111, 110, 101, 192, 13, 0, 0, 128, 1, 163, 116, 119, 111, 24, 252, 255, 255, 128, 2, 165, 116, 104, 114, 101, 101, 208, 7, 0, 0, 255, 5, 128, 100, 129, 204, 200, 255, 6, 128, 205, 44, 1, 129, 205, 144, 1, 255, 7, 128, 205, 244, 1, 129, 205, 88, 2 }

      local state = MapSchemaTypes:new()
      local decoder = Decoder:new(state)

      local callbacks = get_callbacks(decoder)

      local mapOfSchemasOnAddCount = 0
      local mapOfNumbersOnAddCount = 0
      local mapOfStringsOnAddCount = 0
      local mapOfInt32OnAddCount = 0
      callbacks:on_add("mapOfSchemas", function (value, key) mapOfSchemasOnAddCount = mapOfSchemasOnAddCount + 1 end)
      callbacks:on_add("mapOfNumbers", function (value, key) mapOfNumbersOnAddCount = mapOfNumbersOnAddCount + 1 end)
      callbacks:on_add("mapOfStrings", function (value, key) mapOfStringsOnAddCount = mapOfStringsOnAddCount + 1 end)
      callbacks:on_add("mapOfInt32", function (value, key) mapOfInt32OnAddCount = mapOfInt32OnAddCount + 1 end)

      local mapOfSchemasOnRemoveCount = 0
      local mapOfNumbersOnRemoveCount = 0
      local mapOfStringsOnRemoveCount = 0
      local mapOfInt32OnRemoveCount = 0
      callbacks:on_remove("mapOfSchemas", function (value, key) mapOfSchemasOnRemoveCount = mapOfSchemasOnRemoveCount + 1 end)
      callbacks:on_remove("mapOfNumbers", function (value, key) mapOfNumbersOnRemoveCount = mapOfNumbersOnRemoveCount + 1 end)
      callbacks:on_remove("mapOfStrings", function (value, key) mapOfStringsOnRemoveCount = mapOfStringsOnRemoveCount + 1 end)
      callbacks:on_remove("mapOfInt32", function (value, key) mapOfInt32OnRemoveCount = mapOfInt32OnRemoveCount + 1 end)

      local mapOfSchemasOnChangeCount = 0
      local mapOfNumbersOnChangeCount = 0
      local mapOfStringsOnChangeCount = 0
      local mapOfInt32OnChangeCount = 0
      callbacks:on_change("mapOfSchemas", function (value, key) mapOfSchemasOnChangeCount = mapOfSchemasOnChangeCount + 1 end)
      callbacks:on_change("mapOfNumbers", function (value, key) mapOfNumbersOnChangeCount = mapOfNumbersOnChangeCount + 1 end)
      callbacks:on_change("mapOfStrings", function (value, key) mapOfStringsOnChangeCount = mapOfStringsOnChangeCount + 1 end)
      callbacks:on_change("mapOfInt32", function (value, key) mapOfInt32OnChangeCount = mapOfInt32OnChangeCount + 1 end)

      decoder:decode(bytes)

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

      assert_equal(mapOfSchemasOnAddCount, 3);
      assert_equal(mapOfNumbersOnAddCount, 3);
      assert_equal(mapOfStringsOnAddCount, 3);
      assert_equal(mapOfInt32OnAddCount, 3);

      assert_equal(mapOfSchemasOnChangeCount, 3);
      assert_equal(mapOfNumbersOnChangeCount, 3);
      assert_equal(mapOfStringsOnChangeCount, 3);
      assert_equal(mapOfInt32OnChangeCount, 3);

      local delete_bytes = { 255, 2, 64, 1, 64, 2, 255, 1, 64, 1, 64, 2, 255, 3, 64, 1, 64, 2, 255, 4, 64, 1, 64, 2 }
      decoder:decode(delete_bytes)

      assert_equal(state.mapOfSchemas:length(), 1);
      assert_equal(state.mapOfNumbers:length(), 1);
      assert_equal(state.mapOfStrings:length(), 1);
      assert_equal(state.mapOfInt32:length(), 1);

      assert_equal(mapOfSchemasOnRemoveCount, 2);
      assert_equal(mapOfNumbersOnRemoveCount, 2);
      assert_equal(mapOfStringsOnRemoveCount, 2);
      assert_equal(mapOfInt32OnRemoveCount, 2);

      assert_equal(mapOfSchemasOnChangeCount, 5);
      assert_equal(mapOfNumbersOnChangeCount, 5);
      assert_equal(mapOfStringsOnChangeCount, 5);
      assert_equal(mapOfInt32OnChangeCount, 5);

      state:to_raw() -- to_raw() should not throw any errors
    end)

    it("MapSchemaInt8", function()
      local bytes = { 128, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 129, 1, 255, 1, 128, 0, 163, 98, 98, 98, 1, 128, 1, 163, 97, 97, 97, 1, 128, 2, 163, 50, 50, 49, 1, 128, 3, 163, 48, 50, 49, 1, 128, 4, 162, 49, 53, 1, 128, 5, 162, 49, 48, 1 }

      local state = MapSchemaInt8:new()
      local decoder = Decoder:new(state)

      decoder:decode(bytes)

      assert_equal(state.status, "Hello world");
      assert_equal(state.mapOfInt8["bbb"], 1);
      assert_equal(state.mapOfInt8["aaa"], 1);
      assert_equal(state.mapOfInt8["221"], 1);
      assert_equal(state.mapOfInt8["021"], 1);
      assert_equal(state.mapOfInt8["15"], 1);
      assert_equal(state.mapOfInt8["10"], 1);

      local add_bytes = { 255, 1, 0, 5, 2 };
      decoder:decode(add_bytes);

      assert_equal(state.mapOfInt8["bbb"], 1);
      assert_equal(state.mapOfInt8["aaa"], 1);
      assert_equal(state.mapOfInt8["221"], 1);
      assert_equal(state.mapOfInt8["021"], 1);
      assert_equal(state.mapOfInt8["15"], 1);
      assert_equal(state.mapOfInt8["10"], 2);
    end)

    it("InheritedTypesTest", function()
      local serializer = schema_serializer:new()

      local handshake = { 128, 1, 255, 1, 128, 0, 2, 128, 1, 8, 128, 2, 12, 128, 3, 15, 255, 2, 130, 3, 128, 0, 255, 3, 128, 0, 4, 128, 1, 5, 128, 2, 6, 128, 3, 7, 255, 4, 128, 166, 101, 110, 116, 105, 116, 121, 130, 1, 129, 163, 114, 101, 102, 255, 5, 128, 166, 112, 108, 97, 121, 101, 114, 130, 2, 129, 163, 114, 101, 102, 255, 6, 128, 163, 98, 111, 116, 130, 3, 129, 163, 114, 101, 102, 255, 7, 128, 163, 97, 110, 121, 130, 1, 129, 163, 114, 101, 102, 255, 8, 130, 9, 128, 1, 255, 9, 128, 0, 10, 128, 1, 11, 255, 10, 128, 161, 120, 129, 166, 110, 117, 109, 98, 101, 114, 255, 11, 128, 161, 121, 129, 166, 110, 117, 109, 98, 101, 114, 255, 12, 130, 13, 128, 2, 129, 1, 255, 13, 128, 0, 14, 255, 14, 128, 164, 110, 97, 109, 101, 129, 166, 115, 116, 114, 105, 110, 103, 255, 15, 130, 16, 128, 3, 129, 2, 255, 16, 128, 0, 17, 255, 17, 128, 165, 112, 111, 119, 101, 114, 129, 166, 110, 117, 109, 98, 101, 114 }
      serializer:handshake(handshake, { offset = 1 });

      local bytes = { 128, 1, 129, 2, 130, 3, 131, 4, 213, 3, 255, 1, 128, 205, 244, 1, 129, 205, 32, 3, 255, 2, 128, 204, 200, 129, 205, 44, 1, 130, 166, 80, 108, 97, 121, 101, 114, 255, 3, 128, 100, 129, 204, 150, 130, 163, 66, 111, 116, 131, 204, 200, 255, 4, 131, 100 }
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
      state:to_raw() -- to_raw() should not throw any errors
    end)

    it("schema.define() inherited types", function()
      local InheritedTypes = require 'test.schema.InheritedTypes.InheritedTypes'
      local Entity = require 'test.schema.InheritedTypes.Entity'
      local Player = require 'test.schema.InheritedTypes.Player'
      local Bot = require 'test.schema.InheritedTypes.Bot'

      assert_same(InheritedTypes._fields_by_index, { "entity", "player", "bot", "any" })

      assert_equal(#Entity._fields_by_index, 2)
      assert_same(Entity._fields_by_index, { "x", "y" })

      assert_equal(#Player._fields_by_index, 3)
      assert_same(Player._fields_by_index, { "x", "y", "name" })

      assert_equal(#Bot._fields_by_index, 4)
      assert_same(Bot._fields_by_index, { "x", "y", "name", "power" })
    end)

    it("BackwardsForwardsTest", function()
      local statev1bytes = { 129, 1, 128, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 255, 1, 128, 0, 163, 111, 110, 101, 2, 255, 2, 128, 203, 232, 229, 22, 37, 231, 231, 209, 63, 129, 203, 240, 138, 15, 5, 219, 40, 223, 63 }
      local statev2bytes = { 128, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 130, 10 }

      local statev2 = StateV2:new()
      local decoderv2 = Decoder:new(statev2)
      decoderv2:decode(statev1bytes)
      assert_equal(statev2.str, "Hello world")

      local statev1 = StateV1:new()
      local decoderv1 = Decoder:new(statev1)
      decoderv1:decode(statev2bytes);
      assert_equal(statev1.str, "Hello world");
    end)

    it("InstanceSharingTypes", function()
      local state = InstanceSharingTypes:new()
      local decoder = Decoder:new(state)

      decoder:decode({ 130, 1, 131, 2, 128, 3, 129, 3, 255, 3, 128, 4, 255, 4, 128, 10, 129, 10 });
      assert_equal(state.player1, state.player2);
      assert_equal(state.player1.position, state.player2.position);
      assert_equal(decoder.refs.ref_counts[state.player1.__refid], 2);
      assert_equal(5, decoder.refs:count());

      decoder:decode({ 64, 65, 255, 0, 64, 65 });
      assert_equal(nil, state.player1);
      assert_equal(nil, state.player2);
      assert_equal(3, decoder.refs:count());

      decoder:decode({ 255, 1, 128, 0, 5, 128, 1, 5, 128, 2, 5, 128, 3, 7, 255, 5, 128, 6, 255, 6, 128, 10, 129, 10, 255, 7, 128, 8, 255, 8, 128, 10, 129, 10 });
      assert_equal(state.arrayOfPlayers[1], state.arrayOfPlayers[2]);
      assert_equal(state.arrayOfPlayers[2], state.arrayOfPlayers[3]);
      assert_not_equal(state.arrayOfPlayers[3], state.arrayOfPlayers[4]);
      assert_equal(7, decoder.refs:count());

      decoder:decode({ 255, 1, 64, 3, 64, 2, 64, 1 });
      assert_equal(1, state.arrayOfPlayers:length());
      assert_equal(5, decoder.refs:count());
      local previous_array_schema__refid = state.arrayOfPlayers.__refid;

      -- Replacing ArraySchema
      decoder:decode({ 194, 9, 255, 9, 128, 0, 10, 255, 10, 128, 11, 255, 11, 128, 10, 129, 20 });
      assert_equal(false, decoder.refs:has(previous_array_schema__refid));
      assert_equal(1, state.arrayOfPlayers:length());
      assert_equal(5, decoder.refs:count());

      -- Clearing ArraySchema
      decoder:decode({ 255, 9, 10 });
      assert_equal(0, state.arrayOfPlayers:length());
      assert_equal(3, decoder.refs:count());
    end)

    it("Callbacks", function()
      local state = CallbacksState:new()
      local decoder = Decoder:new(state)
      local callbacks = get_callbacks(decoder)

      local on_listen_container = 0
      local on_player_add = 0
      local on_player_remove = 0
      local on_player_change = 0
      local on_item_add = 0
      local on_item_remove = 0
      local on_item_change = 0

      callbacks:listen("container", function (container)
        on_listen_container = on_listen_container + 1

        callbacks:on_add(container, "playersMap", function(player, session_id)
          on_player_add = on_player_add + 1

          callbacks:on_add(player, "items", function (item, key)
            on_item_add = on_item_add + 1
          end)

          callbacks:on_change(player, "items", function (item, key)
            on_item_change = on_item_change + 1
          end)

          callbacks:on_remove(player, "items", function (item, key)
            on_item_remove = on_item_remove + 1
          end)
        end)

        callbacks:on_change(container, "playersMap", function (player, sessionId)
          on_player_change = on_player_change + 1
        end)

        callbacks:on_remove(container, "playersMap", function (player, sessionId)
          on_player_remove = on_player_remove + 1
        end)
      end)

      -- (initial)
      decoder:decode({ 128, 1, 255, 1, 128, 2, 255, 2 })

      -- (1st decode)
      decoder:decode({ 255, 1, 255, 2, 128, 0, 163, 111, 110, 101, 3, 128, 1, 163, 116, 119, 111, 9, 255, 2, 255, 3, 128, 4, 129, 5, 255, 4, 128, 1, 129, 2, 130, 3, 255, 5, 128, 0, 166, 105, 116, 101, 109, 45, 49, 6, 128, 1, 166, 105, 116, 101, 109, 45, 50, 7, 128, 2, 166, 105, 116, 101, 109, 45, 51, 8, 255, 6, 128, 166, 73, 116, 101, 109, 32, 49, 129, 1, 255, 7, 128, 166, 73, 116, 101, 109, 32, 50, 129, 2, 255, 8, 128, 166, 73, 116, 101, 109, 32, 51, 129, 3, 255, 9, 128, 10, 129, 11, 255, 10, 128, 1, 129, 2, 130, 3, 255, 11, 128, 0, 166, 105, 116, 101, 109, 45, 49, 12, 128, 1, 166, 105, 116, 101, 109, 45, 50, 13, 128, 2, 166, 105, 116, 101, 109, 45, 51, 14, 255, 12, 128, 166, 73, 116, 101, 109, 32, 49, 129, 1, 255, 13, 128, 166, 73, 116, 101, 109, 32, 50, 129, 2, 255, 14, 128, 166, 73, 116, 101, 109, 32, 51, 129, 3 })

      assert_equal(1, on_listen_container);
      assert_equal(2, on_player_add);
      assert_equal(2, on_player_change);
      assert_equal(6, on_item_add);
      assert_equal(6, on_item_change);


      -- (2nd decode)
      decoder:decode({ 255, 1, 255, 2, 64, 1, 128, 2, 165, 116, 104, 114, 101, 101, 16, 255, 2, 255, 3, 255, 4, 255, 5, 64, 0, 64, 1, 128, 3, 166, 105, 116, 101, 109, 45, 52, 15, 255, 8, 255, 5, 255, 5, 255, 15, 128, 166, 73, 116, 101, 109, 32, 52, 129, 4, 255, 2, 255, 16, 128, 17, 129, 18, 255, 17, 128, 1, 129, 2, 130, 3, 255, 18, 128, 0, 166, 105, 116, 101, 109, 45, 49, 19, 128, 1, 166, 105, 116, 101, 109, 45, 50, 20, 128, 2, 166, 105, 116, 101, 109, 45, 51, 21, 255, 19, 128, 166, 73, 116, 101, 109, 32, 49, 129, 1, 255, 20, 128, 166, 73, 116, 101, 109, 32, 50, 129, 2, 255, 21, 128, 166, 73, 116, 101, 109, 32, 51, 129, 3 })

      -- (new container)
      decoder:decode({ 128, 22, 255, 2, 255, 5, 255, 5, 255, 2, 255, 0, 255, 22, 128, 23, 255, 23, 128, 0, 164, 108, 97, 115, 116, 24, 255, 24, 128, 25, 129, 26, 255, 25, 128, 10, 129, 10, 130, 10, 255, 26, 128, 0, 163, 111, 110, 101, 27, 255, 27, 128, 166, 73, 116, 101, 109, 32, 49, 129, 1 })

      assert_equal(2, on_listen_container);
      assert_equal(11, on_item_add);
      assert_equal(2, on_item_remove);
      assert_equal(13, on_item_change);

      assert_equal(4, on_player_add);
      assert_equal(5, on_player_change);
      assert_equal(1, on_player_remove);

    end)

  end)

end
