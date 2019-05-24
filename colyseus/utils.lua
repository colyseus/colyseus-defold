local m = {}

function m.table_slice(tbl, first, last, step)
  local sliced = {}

  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced+1] = tbl[i]
  end

  return sliced
end

function m.string_to_byte_array (str)
  local arr = {}
  for i = 1, #str do
    table.insert(arr, string.byte(str, i, i))
  end
  return arr
end

function m.byte_array_to_string (arr)
  local str = ''
  for i = 1, #arr do
    str = str .. string.char(arr[i])
  end
  return str
end

local char_to_hex = function(c)
  return string.format("%%%02X", string.byte(c))
end

function m.urlencode (url)
  if url == nil then
    return
  end
  url = url:gsub("\n", "\r\n")
  url = url:gsub("([^%w ])", char_to_hex)
  url = url:gsub(" ", "+")
  return url
end

return m
