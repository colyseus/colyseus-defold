local m = {}

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

return m
