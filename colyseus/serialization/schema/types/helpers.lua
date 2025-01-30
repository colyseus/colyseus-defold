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


-- --
-- -- ordered_array
-- -- the ordered array is used to keep track of "all_changes", and ordered ref_id per change, as they are identified.
-- --
-- local ordered_array = {}
-- function ordered_array:new(obj)
    -- obj = {
        -- items = {},
        -- keys = {},
    -- }
    -- setmetatable(obj, ordered_array)
    -- return obj
-- end
-- function ordered_array:__index(key)
    -- return (type(key)=="number") and self.items[key] or rawget(self, key)
-- end
-- function ordered_array:__newindex(key, value)
    -- self.items[key] = value
    -- table.insert(self.keys, key)
-- end

return M