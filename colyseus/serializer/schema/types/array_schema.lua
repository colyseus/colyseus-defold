local utils = require("colyseus.serializer.schema.utils")
local constants = require 'colyseus.serializer.schema.constants'
local OPERATION = constants.OPERATION;

--
-- Lua Language Server doesn't support generics like this yet.
-- https://github.com/LuaLS/lua-language-server/issues/2945
-- ---@class ArraySchema<T>: { [integer]: T }
--

---@class ArraySchema
---@field __refid integer
---@field private items table
---@field private props table
local ArraySchema = {}
ArraySchema.__index = ArraySchema

function ArraySchema:new(obj)
  obj = obj or {
    items = {},
    props = {},
  }
  setmetatable(obj, ArraySchema)
  return obj
end

--
-- TODO:
-- Defold currently relies on Lua 5.1
-- In order to support #myArray to retrieve its length (hence calling __len) - Lua 5.2 is required.
--
-- function array_schema:__len()
--   return #self.items
-- end

-- length (counts actual items, excluding nil holes)
function ArraySchema:length()
  local count = 0
  for i, v in pairs(self.items) do
    if type(i) == "number" and v ~= nil then
      count = count + 1
    end
  end
  return count
end

-- getter
function ArraySchema:__index(key)
  if ArraySchema[key] ~= nil then
    return ArraySchema[key]
  else
    return type(key) == "number"
      and self.items[key]
      or self.props[key]
  end
end

-- setter
function ArraySchema:__newindex(key, value)
  if type(key) == "number" then
    self.items[key] = value
  else
    self.props[key] = value
  end
end

function ArraySchema:index_of(value)
  for i, v in pairs(self.items) do
    if v == value then
      return i
    end
  end
  return -1
end

---@package
function ArraySchema:set_by_index(index, value, operation)
  -- strict ADD only: MOVE_AND_ADD/DELETE_AND_ADD/ADD_BY_REFID must not insert
  if operation == OPERATION.ADD and self.items[index] ~= nil then
    -- ADD at an occupied index = insert: shift existing items up.
    table.insert(self.items, index, value)
  elseif operation == OPERATION.DELETE_AND_MOVE then
    table.remove(self.items, index)
    self.items[index] = value
  else
    self.items[index] = value
  end
end

---@package
function ArraySchema:get_by_index(index)
  return self.items[index]
end

---@package
function ArraySchema:delete_by_index(index)
  self.items[index] = nil
end

function ArraySchema:each(cb)
  for index, value in pairs(self.items) do
    if type(index) == "number" then
      cb(value, index)
    end
  end
end

function ArraySchema:clone()
  return ArraySchema:new({
    items = table.clone(self.items),
    props = self.props,
  })
end

function ArraySchema:to_json()
  local map = {}
  self:each(function(value, key)
    if type(value) == "table" and type(value['to_json']) == "function" then
      map[key] = value:to_json()
    else
      map[key] = value
    end
  end)
  return map
end

---@package
function ArraySchema:clear(changes, refs)
  utils.remove_child_refs(self, changes, refs)
  self.items = {}
end

---@package
function ArraySchema:reverse()
  -- first collect all items with their indices
  local indices = {}
  for i, v in pairs(self.items) do
    if type(i) == "number" and v ~= nil then
      table.insert(indices, i)
    end
  end
  table.sort(indices)

  -- reverse the values
  local n = #indices
  local reversed = {}
  for i = 1, n do
    reversed[i] = self.items[indices[n - i + 1]]
  end
  self.items = reversed
end

---@package
function ArraySchema:__on_decode_end()
  local new_items = {}
  -- collect all non-nil values with their indices for proper sorting
  local indices = {}
  for i, v in pairs(self.items) do
    if type(i) == "number" and v ~= nil then
      table.insert(indices, i)
    end
  end
  -- sort indices to maintain order
  table.sort(indices)
  -- rebuild compacted array
  for _, i in ipairs(indices) do
    table.insert(new_items, self.items[i])
  end
  self.items = new_items
end

return ArraySchema
