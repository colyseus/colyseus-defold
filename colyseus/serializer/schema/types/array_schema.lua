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
-- `items` is dense between decodes, so `#items` is its length. A nil write or
-- a write past the end leaves a hole `#` can't see across: `_sparse` marks it
-- until the next compaction, and the readers walk the sorted indexes instead.
--
local function track_write(self, index, value)
  if value == nil or index > #self.items + 1 then rawset(self, "_sparse", true) end
end

local function sorted_indexes(items)
  local indexes = {}
  for i in pairs(items) do
    if type(i) == "number" then table.insert(indexes, i) end
  end
  table.sort(indexes)
  return indexes
end

--
-- TODO:
-- Defold currently relies on Lua 5.1
-- In order to support #myArray to retrieve its length (hence calling __len) - Lua 5.2 is required.
--
-- function array_schema:__len()
--   return #self.items
-- end

--- Number of items, nil holes excluded.
---@return number
function ArraySchema:length()
  if not rawget(self, "_sparse") then return #self.items end
  local count = 0
  for i in pairs(self.items) do
    if type(i) == "number" then count = count + 1 end
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
    track_write(self, key, value)
    self.items[key] = value
  else
    self.props[key] = value
  end
end

--- Index of the first item equal to `value`, or -1.
---@return integer
function ArraySchema:index_of(value)
  local items = self.items
  if not rawget(self, "_sparse") then
    for i = 1, #items do
      if items[i] == value then return i end
    end
  else
    for _, i in ipairs(sorted_indexes(items)) do
      if items[i] == value then return i end
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
    track_write(self, index, value)
    self.items[index] = value
  else
    track_write(self, index, value)
    self.items[index] = value
  end
end

---@package
function ArraySchema:get_by_index(index)
  return self.items[index]
end

---@package
function ArraySchema:delete_by_index(index)
  rawset(self, "_sparse", true)
  self.items[index] = nil
end

--
-- Resync sweep (see Decoder:decode_resync): remove every entry whose index
-- the snapshot did not visit. `items` is hole-free here (decode-end
-- compaction already ran; full-sync emits dense ADDs). Visited indexes may
-- be sparse — ADD_BY_REFID resolves to the current client-side index.
--
function ArraySchema:__resync_prune(visited, prune, keep)
  local removed = false
  for i = 1, #self.items do
    local value = self.items[i]
    if visited[i] then
      keep(value)
    else
      removed = true
      prune(value, i)
      self:delete_by_index(i)
    end
  end
  if removed then self:__on_decode_end() end -- compact the holes
end

--- Calls `cb(value, index)` for every item, in index order.
---@param cb fun(value: any, index: integer)
function ArraySchema:each(cb)
  local items = self.items
  if not rawget(self, "_sparse") then
    for i = 1, #items do cb(items[i], i) end
  else
    for _, i in ipairs(sorted_indexes(items)) do cb(items[i], i) end
  end
end

function ArraySchema:clone()
  return ArraySchema:new({
    items = table.clone(self.items),
    props = self.props,
    _sparse = rawget(self, "_sparse"),
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
  rawset(self, "_sparse", nil)
end

---@package
function ArraySchema:reverse()
  local indexes = sorted_indexes(self.items)
  local n = #indexes
  local reversed = {}
  for i = 1, n do
    reversed[i] = self.items[indexes[n - i + 1]]
  end
  self.items = reversed
  rawset(self, "_sparse", nil)
end

---@package
function ArraySchema:__on_decode_end()
  if not rawget(self, "_sparse") then return end -- already dense
  local new_items = {}
  for _, i in ipairs(sorted_indexes(self.items)) do
    table.insert(new_items, self.items[i])
  end
  self.items = new_items
  rawset(self, "_sparse", nil)
end

return ArraySchema
