local map_schema = {}
map_schema.__index = map_schema

function map_schema:new(obj)
  obj = obj or {
    items = {},
    keys = {},
    indexes = {},
    props = {},
  }
  setmetatable(obj, map_schema)
  return obj
end

-- getter
function map_schema:__index(key)
  if map_schema[key] ~= nil then
    return map_schema[key]
  else
    return self.props[key] ~= nil
      and self.props[key]
      or self.items[key]
  end
end

-- setter
function map_schema:__newindex(key, value)
  -- if type(key) == "number" then
  --   self.items[key] = value
  -- else
  --   self.props[key] = value
  -- end
  self.props[key] = value
end

function map_schema:set_index(index, dynamic_index)
  self.indexes[index] = dynamic_index
end

function map_schema:set_by_index(index, dynamic_index, value)
  self.indexes[index] = dynamic_index

  -- insert key
  if self.items[dynamic_index] == nil then
      table.insert(self.keys, dynamic_index)
  end

  -- insert value
  self.items[dynamic_index] = value
end

function map_schema:get_index(index)
  return self.indexes[index]
end

function map_schema:get_by_index(index)
  return self.items[self.indexes[index]]
end

function map_schema:delete_by_index(index)
  local dynamic_index = self.indexes[index]

  -- delete key
  for i, k in pairs(self.keys) do
    if k == dynamic_index then
      table.remove(self.keys, i)
      break
    end
  end

  self.items[dynamic_index] = nil
  self.indexes[index] = nil
end

function map_schema:clear(refs)
  if self._child_type['_schema'] ~= nil then
    self:each(function(item)
      refs:remove(item.__refid)
    end)
  end

  self.indexes = {}
  self.items = {}
end

function map_schema:length()
    return #self.indexes
end

function map_schema:keys()
    return self.keys
end

function map_schema:values()
    local values = {}
    for _, key in ipairs(self.keys) do
        table.insert(values, self.items[key])
    end
    return values
end

function map_schema:each(cb)
    for _, key in ipairs(self.keys) do
        cb(self.items[key], key)
    end
end

function map_schema:trigger_all()
  if type(self) ~= "table" or self['on_add'] == nil then return end
  for _, key in pairs(self.keys) do
    self['on_add'](self.items[key], key)
  end
end

function map_schema:clone()
  return map_schema:new({
    items = table.clone(self.items),
    indexes = table.clone(self.indexes),
    keys = table.clone(self.keys),
    props = self.props,
  })

  -- for _, key in ipairs(self.keys) do
  --   cloned:set(key, self.items[key])
  -- end

  -- cloned['on_add'] = self['on_add']
  -- cloned['on_remove'] = self['on_remove']
  -- cloned['on_change'] = self['on_change']

  -- return cloned
end

return map_schema
