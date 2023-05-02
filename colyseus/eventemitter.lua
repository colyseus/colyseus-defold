--
-- Based on https://github.com/wscherphof/lua-events/
--

---@class EventEmitterObject

---@class EventEmitter
local EventEmitter = {}

function table_find(tab,el)
  for index, value in pairs(tab) do
    if value == el then
      return index
    end
  end
end

---@param object EventEmitterObject|nil
---@return EventEmitterObject
function EventEmitter:new(object)

  object = object or {}
  object._on = {}
  object._once = {}

  function object:on (event, listener)
    self._on[event] = self._on[event] or {}
    table.insert(self._on[event], listener)
    return listener
  end

  function object:once (event, listener)
    self._once[event] = listener
    return self:on(event, listener)
  end

  function object:off (event, listener)
    if event then
      -- clear from "once"
      self._once[event] = nil
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

        -- clear from "once"
        if self._once[event] == listener then
          self:off(event, listener)
        end
      end
    end
  end

  return object
end

return EventEmitter
