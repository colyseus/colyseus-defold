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

    it("off(event) removes every listener of that event", function()
      local e, _, fired = emitter("a", "b", "c")
      e:on("y", function() end)

      e:off("x")
      assert_equal("", fired())
      assert_equal(1, #e:listeners("y"))

      e:off("z") -- no listener on "z" at all
    end)

    it("off() removes every listener", function()
      local e, _, fired = emitter("a", "b")
      e:on("y", function() end)
      e:on("y", function() end)

      e:off()
      assert_equal("", fired())
      assert_equal(0, #e:listeners("y"))
    end)

  end)
end
