local schema = require 'colyseus.serialization.schema.schema'

return function()

  local State = schema.define({
    ["fieldString"] = "string",
    ["_order"] = { "fieldString" },
  });

  describe("colyseus", function()
    describe("schema serializer", function()
      it("should decode complex UTF-8 characters", function()
        local bytes = { 0, 166, 208, 179, 209, 133, 208, 177 }

        local state = State:new()
        state:decode(bytes);

        assert_same(state.fieldString, "гхб")
      end)

    end)
  end)
end
