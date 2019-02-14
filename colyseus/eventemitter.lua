--
-- Based on https://github.com/wscherphof/lua-events/
--

local EventEmitter = {}

function table_find(tab,el)
  for index, value in pairs(tab) do
    if value == el then
      return index
    end
  end
end

function EventEmitter:new(object)

  object = object or {}
  object._on = {}

  function object:on (event, listener)
    self._on[event] = self._on[event] or {}
    table.insert(self._on[event], listener)
    return listener
  end

  function object:off (event, listener)
    if event then
      if not listener then
        table.remove(self._on[event])
      else
        table.remove(self._on[event], table_find(self._on[event], listener))
      end
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
    for _, listener in ipairs(self:listeners(event)) do
      if "function" == type(listener) then
        listener(...)
      end
    end
  end

  return object
end

return EventEmitter
