--
-- schema callback helpers
--

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
    print("EXISTING?", existing:length())
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

function M.remove_child_refs(collection, changes)
  -- local need_remove_ref =  (typeof (this.$changes.getType()) !== "string");

  -- this.$items.forEach((item: any, key: any) => {
  --     changes.push({
  --         refId: this.$changes.refId,
  --         op: OPERATION.DELETE,
  --         field: key,
  --         value: undefined,
  --         previousValue: item
  --     });

  --     if (need_remove_ref) {
  --         this.$changes.root.removeRef(item['$changes'].refId);
  --     }
  -- });
end

return M