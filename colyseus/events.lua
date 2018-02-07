--
-- Based on https://github.com/wscherphof/lua-events/
--

local EventEmitter = {}

function EventEmitter:new(object)

  object = object or {}
  object._on = {}

  function object:on (event, listener)
    self._on[event] = self._on[event] or {}
    table.insert(self._on[event], listener)
  end

  function object:off (event)
    if event then
      table.remove(self._on[event])
    else
      for event, listener in ipairs(self._on) do
        self:off(event)
      end
    end
  end

  function object:listeners (event)
    return self._on[event] or {}
  end

  function object:emit (event, ...)
    for _,listener in ipairs(self:listeners(event)) do
      if "function" == type(listener) then
        listener(...)
      end
    end
  end

  return object

end

return {
  EventEmitter = EventEmitter
}
