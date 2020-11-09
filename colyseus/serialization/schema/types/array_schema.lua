local array_schema = {}

function array_schema:new(obj)
  obj = obj or {
    items = {},
    keys = {},
    indexes = {},
    props = {},
  }
  setmetatable(obj, array_schema)
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

-- length
function array_schema:length()
  return #self.items
end

-- getter
function array_schema:__index(key)
  if array_schema[key] ~= nil then
    return array_schema[key]
  else
    return type(key) == "number"
      and self:get_by_index(key)
      or self.props[key]
  end
end

-- setter
function array_schema:__newindex(key, value)
  if type(key) == "number" then
    -- self:set_by_index(key, key, value)
    self.items[key] = value
  else
    self.props[key] = value
  end
end

function array_schema:set_index(index, dynamic_index)
  self.indexes[index] = dynamic_index
end

function array_schema:set_by_index(index, dynamic_index, value)
  self.indexes[index] = dynamic_index

  -- insert key
  if self.items[dynamic_index] == nil then
      table.insert(self.keys, dynamic_index)
  end

  self.items[dynamic_index] = value
end

function array_schema:get_index(index)
  return self.indexes[index]
end

function array_schema:get_by_index(index)
  return self.items[self.keys[index]]
end

function array_schema:delete_by_index(index)
  local dynamic_index = self.indexes[index]

  -- delete key
  for i, k in pairs(self.keys) do
    if k == dynamic_index then
      table.remove(self.keys, i)
      break
    end
  end

  self.items[dynamic_index] = nil
  self.indexes[dynamic_index] = nil
end

function array_schema:clear(refs)
  if self._child_type['_schema'] ~= nil then
    self:each(function(item)
      refs:remove(item.__refid)
    end)
  end

  self.indexes = {}
  self.items = {}
end

function array_schema:trigger_all()
  if type(self) ~= "table" or self['on_add'] == nil then return end
  for _, dynamic_index in ipairs(self.indexes) do
    self['on_add'](self.items[dynamic_index], dynamic_index)
  end
end

function array_schema:each(cb)
  for _, dynamic_index in ipairs(self.indexes) do
    cb(self.items[dynamic_index], dynamic_index)
  end
end

function array_schema:clone()
  return array_schema:new({
    items = table.clone(self.items),
    keys = table.clone(self.keys),
    indexes = table.clone(self.indexes),
    props = self.props,
  })
end

return array_schema
