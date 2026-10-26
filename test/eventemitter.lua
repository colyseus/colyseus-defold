local EventEmitter = require 'colyseus.eventemitter'

--- An emitter with one listener on "x" per name given, the listeners by name,
--- and `fired()`, which emits "x" and returns the names called, in order.
local function emitter(...)
  local e, listeners, calls = EventEmitter:new(), {}, {}
  for _, name in ipairs({ ... }) do
    listeners[name] = function() table.insert(calls, name) end
    e:on("x", listeners[name])
  end
  local function fired()
    calls = {}
    e:emit("x")
    return table.concat(calls, ",")
  end
  return e, listeners, fired
end

return function()
  describe("colyseus.eventemitter", function()

    it("off() with a listener that isn't registered removes nothing", function()
      local e, listeners, fired = emitter("a", "b")

      e:off("x", function() end)
      assert_equal("a,b", fired())

      e:off("x", listeners.a)
      e:off("x", listeners.a)
      assert_equal("b", fired())

      e:off("y", listeners.b) -- no listener on "y" at all
      assert_equal("b", fired())
    end)

  end)
end
