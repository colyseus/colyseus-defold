local map_schema = {}
map_schema.__index = map_schema

function map_schema:new(obj)
    obj = { __keys = {} }
    setmetatable(obj, map_schema)
    return obj
end

function map_schema:set(key, value)
    if value == nil then
        -- delete!
        for i, k in pairs(self.__keys) do
            if k == key then
                table.remove(self.__keys, i)
                break
            end
        end

        self[key] = nil
    else
        -- insert!
        if not self[key] then
            table.insert(self.__keys, key)
        end
        self[key] = value
    end
end

function map_schema:length()
    return #self.__keys
end

function map_schema:keys()
    return self.__keys
end

function map_schema:values()
    local values = {}
    for _, key in ipairs(self.__keys) do
        table.insert(values, self[key])
    end
    return values
end

function map_schema:each(cb)
    for _, key in ipairs(self.__keys) do
        cb(self[key], key)
    end
end

function map_schema:trigger_all()
    if type(self) ~= "table" or self['on_add'] == nil then return end
    for key, value in pairs(self) do
        if key ~= 'on_add' and key ~= 'on_remove' and key ~= 'on_change' and key ~= '__keys' then
            self['on_add'](value, key)
        end
    end
end

function map_schema:clone()
    local cloned = map_schema:new()

    for _, key in ipairs(self.__keys) do
        cloned:set(key, self[key])
    end

    cloned['on_add'] = self['on_add']
    cloned['on_remove'] = self['on_remove']
    cloned['on_change'] = self['on_change']

    return cloned
end

return map_schema
