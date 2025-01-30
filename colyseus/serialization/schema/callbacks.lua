local bit = require 'colyseus.serialization.bit'
local callback_helpers = require 'colyseus.serialization.schema.types.helpers'
local constants = require 'colyseus.serialization.schema.constants'
local OPERATION = constants.OPERATION;

Callbacks = {}

function Callbacks.new()
	local self = setmetatable({}, { __index = Callbacks })
	return self
end

function Callbacks:on_change(callback)
  if self.__callbacks == nil then self.__callbacks = {} end
  return callback_helpers.add_callback(self.__callbacks, OPERATION.REPLACE, callback);
end

function Callbacks:on_remove(callback)
  if self.__callbacks == nil then self.__callbacks = {} end
  return callback_helpers.add_callback(self.__callbacks, OPERATION.DELETE, callback);
end

function Callbacks:listen(field_name, callback, immediate)
  if self.__callbacks == nil then self.__callbacks = {} end
  if self.__callbacks[field_name] == nil then self.__callbacks[field_name] = {} end

  table.insert(self.__callbacks[field_name], callback)

  if immediate == nil then immediate = true end -- "immediate" is true by default
  if immediate and self[field_name] ~= nil then
    callback(self[field_name])
  end

  -- return un-register callback.
  return function()
    for index, value in pairs(self.__callbacks[field_name]) do
      if value == callback then
        table.remove(self.__callbacks[field_name], index)
        break
      end
    end
  end
end

function Callbacks:_trigger_changes(changes, refs)
  local unique_ref_ids = {}

  for _, change in pairs(changes) do
    repeat
      local ref_id = change.__refid
      local ref = refs:get(ref_id)
      local is_schema = (ref['_schema'] ~= nil)
      local callbacks = ref.__callbacks

      --
      -- trigger on_remove() on child structure.
      --
      if (
        bit.band(change.op, OPERATION.DELETE) == OPERATION.DELETE and
        type(change.previous_value) == "table" and
        change.previous_value['_schema'] ~= nil
      ) then
        local delete_callbacks = (change.previous_value.__callbacks and change.previous_value.__callbacks[OPERATION.DELETE])
        if delete_callbacks then
          for _, callback in pairs(delete_callbacks) do
            callback()
          end
        end
      end

      -- "continue" if no callbacks are set
      if callbacks == nil then break end

      if is_schema then
        -- is schema

        -- ensure on_change() is triggered only once per schema instance.
        if unique_ref_ids[ref_id] == nil then
          local replace_callbacks = callbacks[OPERATION.REPLACE]
          if replace_callbacks ~= nil then
            for _, callback in pairs(replace_callbacks) do
              callback(changes)
            end
          end
        end

        local field_callbacks = callbacks[change.field]
        if field_callbacks ~= nil then
          for _, callback in pairs(field_callbacks) do
            callback(change.value, change.previous_value)
          end
        end

      else
        -- is a collection/custom type

        if change.op == OPERATION.ADD and change.previous_value == nil then
          local add_callbacks = callbacks[OPERATION.ADD]
          if add_callbacks ~= nil then
            for _, callback in pairs(add_callbacks) do
              callback(change.value, change.dynamic_index)
            end
          end

        elseif change.op == OPERATION.DELETE then
          --
          -- FIXME: `previous_value` should always be available.
          -- ADD + DELETE operations are still encoding DELETE operation.
          --
          local delete_callbacks = callbacks[OPERATION.DELETE]
          if change.previous_value ~= nil and delete_callbacks ~= nil then
            for _, callback in pairs(delete_callbacks) do
              callback(change.previous_value, change.dynamic_index or change.field)
            end
          end

        elseif change.op == OPERATION.DELETE_AND_ADD then
          local delete_callbacks = callbacks[OPERATION.DELETE]
          if change.previous_value ~= nil and delete_callbacks ~= nil then
            for _, callback in pairs(delete_callbacks) do
              callback(change.previous_value, change.dynamic_index)
            end
          end

          local add_callbacks = callbacks[OPERATION.ADD]
          if add_callbacks ~= nil then
            for _, callback in pairs(add_callbacks) do
              callback(change.value, change.dynamic_index)
            end
          end
        end

        if change.value ~= change.previous_value then
          local replace_callbacks = callbacks[OPERATION.REPLACE]
          if replace_callbacks ~= nil then
            for _, callback in pairs(replace_callbacks) do
              callback(change.value, change.dynamic_index or change.field)
            end
          end
        end
      end

      unique_ref_ids[ref_id] = true

      break
    until true
  end
end

return Callbacks