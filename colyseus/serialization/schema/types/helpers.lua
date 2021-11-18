--
-- schema callback helpers
--

local constants = require 'colyseus.serialization.schema.constants'
local OPERATION = constants.OPERATION;

local M = {}

function M.add_callback(__callbacks, op, callback, existing)
  -- initialize list of callbacks
  if __callbacks[op] == nil then __callbacks[op] = {} end

  table.insert(__callbacks[op], callback)

  --
  -- Trigger callback for existing elements
  -- - OPERATION.ADD
  -- - OPERATION.REPLACE
  --
  if existing ~= nil then
    existing:each(function(item, key)
      callback(item, key)
    end)
  end

  -- return a callback that removes the callback when called
  return function()
    for index, value in pairs(__callbacks[op]) do
      if value == callback then
        table.remove(__callbacks[op], index)
        break
      end
    end
  end
end

function M.remove_child_refs(collection, changes, refs)
  local need_remove_ref = (collection._child_type['_schema'] ~= nil);

  collection:each(function(item, key)
      table.insert(changes, {
          __refid = collection.__refid,
          op = OPERATION.DELETE,
          field = key,
          value = nil,
          previous_value = item
      })

      if need_remove_ref then
          refs:remove(item.__refid)
      end
  end)
end

return M