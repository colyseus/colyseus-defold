function compare(tree1, tree2)
  local patches = {}
  generate(tree1, tree2, patches, {})
  return patches;
end

local function concat(arr, value)
  local newArr = { table.unpack(arr) } -- copy array
  table.insert(newArr, value)
  return newArr
end

local function is_array(t)
  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil then return false end
  end
  return true
end

local function table_keys (obj)
  local keys = {}
  local length = 0

  if (is_array(obj)) then
    for k, v in pairs(obj) do
      table.insert(keys, tostring(k-1))
      length = length + 1
    end

  else
    for k, v in pairs(obj) do
      table.insert(keys, k)
      length = length + 1
    end
  end

  keys["length"] = length
  return keys
end

-- Dirty check if obj is different from mirror, generate patches and update mirror
function generate(mirror, obj, patches, path)
  local newKeys = table_keys(obj)
  local oldKeys = table_keys(mirror)
  local changed = false
  local deleted = false

  -- for (local t = oldKeys.length - 1; t >= 0; t--) {
  for t = oldKeys["length"], 1, -1 do
      local key = oldKeys[t]
      local oldVal = mirror[key]

      if obj[key] ~= nil and not (obj[key] == nil and oldVal ~= nil and not is_array(obj)) then
          local newVal = obj[key]

          if type(oldVal) == "table" and oldVal ~= nil and type(newVal) == "table" and newVal ~= nil then
              generate(oldVal, newVal, patches, concat(path, key));

          else
              if oldVal ~= newVal then
                  changed = true

                  patches.push({
                    operation = "replace",
                    path = concat(path, key),
                    value = newVal
                  })
              end
          end
      else
          patches.push({
            operation = "remove",
            path = concat(path, key)
          })
          deleted = true -- property has been deleted
      end
  end

  if not deleted and newKeys["length"] == oldKeys["length"] then
      return
  end

  -- for (local t = 0; t < newKeys.length; t++) {
  for t = 1, newKeys["length"] do
    local key = newKeys[t]

    if mirror[key] == nil and obj[key] ~= nil then
      local newVal = obj[key]
      local addPath = concat(path, key)

      -- compare deeper additions
      if type(newVal) == "table" and newVal ~= nil then
          generate({}, newVal, patches, addPath)
      end

      patches.push({
        operation = "add",
        path = addPath,
        value = newVal
      })
    end
  end
end

return compare
