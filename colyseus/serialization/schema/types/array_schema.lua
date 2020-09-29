local array_schema = {}

function array_schema:new(obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function array_schema:trigger_all()
    if type(self) ~= "table" or self['on_add'] == nil then return end
    for key, value in ipairs(self) do
        if key ~= 'on_add' and key ~= 'on_remove' and key ~= 'on_change' then
            self['on_add'](value, key)
        end
    end
end

function array_schema:each(cb)
    for key, value in ipairs(self) do
        if key ~= 'on_add' and key ~= 'on_remove' and key ~= 'on_change' then
            cb(value, key)
        end
    end
end

function array_schema:clone()
    local cloned = array_schema:new(table.clone(self))
    cloned['on_add'] = self['on_add']
    cloned['on_remove'] = self['on_remove']
    cloned['on_change'] = self['on_change']
    return cloned
end

return array_schema