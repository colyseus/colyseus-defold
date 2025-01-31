local bit = require 'colyseus.serializer.bit'
local constants = require 'colyseus.serializer.schema.constants'
local OPERATION = constants.OPERATION;

---@class Callbacks
---@field private decoder Decoder
Callbacks = {}
Callbacks.__index = Callbacks

---@package
---@return Callbacks
function Callbacks:new(decoder)
	local instance = {
    decoder = decoder
  }
  setmetatable(instance, Callbacks)
  -- assign decoder's _trigger_changes to this instance.
  decoder._trigger_changes = instance._trigger_changes
	return instance
end

---@param instance Schema
---@param callback fun() callback to be called when any property of provided instance changes.
---@return fun() un-register callback
function Callbacks:on_change(instance, callback)
  return callback_helpers.add_callback(self.__callbacks, OPERATION.REPLACE, callback);
end

---@param instance_or_field Schema|string
---@param callback_or_field string|fun(value: any, key: any)
---@param callback nil|fun(value: any, key: any)
function Callbacks:on_add(instance_or_field, callback_or_field, callback)
  local instance = self.decoder.state
  local field = instance_or_field

  if type(instance_or_field) ~= "string" then
    instance = instance_or_field
    field = callback_or_field

  else
    callback = callback_or_field
  end

  return self:add_callback(instance.__refid, field, callback)
end

function Callbacks:on_remove(callback)
  return callback_helpers.add_callback(self.__callbacks, OPERATION.DELETE, callback);
end

---@param instance_or_field Schema|string
---@param callback_or_field string|fun(value: any, previous_value: any)
---@param callback nil|fun(value: any, previous_value: any)
---@param immediate boolean|nil
function Callbacks:listen(instance_or_field, callback_or_field, callback, immediate)
  local instance = self.decoder.state
  local field = instance_or_field

  if type(instance_or_field) ~= "string" then
    instance = instance_or_field
    field = callback_or_field

  else
    callback = callback_or_field
  end

  return self:add_callback(instance.__refid, field, callback)
end

---@package
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

---@package
function Callbacks:add_callback_or_wait_collection_available(instance, field_name, operation, callback)
  local _self = self

  local remove_handler = function() end
  local remove_on_add = function() remove_handler() end

  if instance[field_name] == nil then
    remove_handler = _self:listen(instance, field_name, function(collection, _)
      remove_handler = _self:add_callback(collection.__refid, operation, callback)
    end)
    return remove_on_add
  else
    return _self:add_callback(instance[field_name].__refid, operation, callback)
  end
end

---@param __refid number
---@param operation_or_field string
---@param callback fun(value: any, key: any)
---@package
function Callbacks:add_callback(__refid, operation_or_field, callback)
  print("ADD CALLBACK, __refid:", __refid, "operation_or_field:", operation_or_field)

  local handlers = self.decoder.refs.callbacks[__refid]

  if handlers == nil then
    handlers = {}
    self.decoder.refs.callbacks[__refid] = handlers
  end

  if handlers[operation_or_field] == nil then
    handlers[operation_or_field] = {}
  end

  table.insert(handlers[operation_or_field], callback)

  -- return a callback that removes the callback when called
  return function()
    for index, value in pairs(handlers[operation_or_field]) do
      if value == callback then
        table.remove(handlers[operation_or_field], index)
        break
      end
    end
  end
end

---@param room_or_decoder Room|Decoder
---@return Callbacks
return function(room_or_decoder)
  if room_or_decoder.room_id ~= nil then
    return Callbacks:new(room_or_decoder.serializer.decoder)

  elseif room_or_decoder._trigger_changes ~= nil then
    return Callbacks:new(room_or_decoder)
  end
end
