local schema = require 'colyseus.serialization.schema.schema'

return function()
  describe("colyseus", function()

    describe("schema serializer", function()
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

    describe("PrimitiveTypes", function()
      local PrimitiveTypes = require 'test.schema.PrimitiveTypes.PrimitiveTypes'

      it("should support decoding primitive types", function()
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

        -- This is not right!
        -- assert_equal(state.float32, -3.40282347E+37);
        -- assert_equal(state.float32, 5.9006092937051e-39);

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

        -- This is not right!
        -- assert_equal(state.varint_float64, 1.7976931348623e+308);

        assert_equal(state.str, "Hello world");
        assert_equal(state.boolean, true);

      end)
    end)

  end)
end
