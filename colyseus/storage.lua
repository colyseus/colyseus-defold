local storage = {}
local data = {}

-- resolved on first use: `sys` is an engine global, absent outside Defold
local storage_file_path
local function file_path()
  storage_file_path = storage_file_path or sys.get_save_file("colyseus", "storage")
  return storage_file_path
end

function storage.get_item (key)
  if sys == nil then return data[key] or "" end -- outside the engine: memory only
  data = sys.load(file_path())
  return data[key] or ""
end

function storage.set_item (key, value)
  data[key] = value

  if sys == nil then return end
  if not sys.save(file_path(), data) then
    print("colyseus.client: storage.set_item couldn't set '" .. key .. "' locally.")
  end
end

return storage
