local compare = require('colyseus.delta_listener.compare').compare

DeltaContainer = {}
DeltaContainer.__index = DeltaContainer

function DeltaContainer.new ()
  local instance = EventEmitter:new({
    data = {},
    defaultListener = nil,
  })
  setmetatable(instance, DeltaContainer)
  instance:init()
  return instance
end

  -- private matcherPlaceholders: {[id: string]: RegExp} = {
  --   ":id": /^$/,
  --   ":number": /^([0-9]+)$/,
  --   ":string": /^(\w+)$/,
  --   ":axis": /^([xyz])$/,
  --   ":*": /(.*)/,
  -- }

function DeltaContainer:init ()
  self.data = data;

  self.matcherPlaceholders = {}
  self.matcherPlaceholders[":id"] = "^([%a%d-_]+)$"
  self.matcherPlaceholders[":number"] = "^(%d+)$"
  self.matcherPlaceholders[":string"] = "^(%a+)$"
  self.matcherPlaceholders[":axis"] = "^([xyz])$"
  self.matcherPlaceholders[":*"] = "^(.*)$"

  self:reset()
end

function DeltaContainer:set (newData)
  local patches = compare(self.data, newData);
  self.check_patches(patches)
  self.data = newData
  return patches
end

function DeltaContainer:register_placeholder (placeholder, matcher)
  self.matcherPlaceholders[placeholder] = matcher
end

function DeltaContainer:listen (segments, callback)
  local rules

  if type(segments) == "function" then
    rules = {}
    callback = segments

  else
    rules = split(segments, "/")
  end

  if table.getn(callback) > 1 then
    console.warn(".listen() accepts only one parameter.");
  end

  local listener = {
    callback = callback,
    rawRules = rules,
    rules = map(rules, function(segment)
      if type(segment) == "string" then
        -- replace placeholder matchers
        return (string.find(segment, ":") == 1)
          and (self.matcherPlaceholders[segment] or self.matcherPlaceholders[":*"])
          or "^" .. segment .. "$"
      else
        return segment
      end
    end)
  };

  if (table.getn(rules) == 0) then
    self.defaultListener = listener

  else
    table.push(self.listeners, listener)
  end

  return listener
end

function DeltaContainer:remove_listener (listener)
  for k, l in ipairs(self.listeners) do
    if l == listener then
      self.listeners[k] = nil
    end
  end
end

function DeltaContainer:remove_all_listeners ()
  self:reset()
end

function DeltaContainer:check_patches (patches)
  -- for (let i = patches.length - 1; i >= 0; i--) {
  for i = table.getn(patches), 1, -1 do
    local matched = false

    -- for (let j = 0, len = this.listeners.length; j < len; j++) {
    for j = table.getn(self.listeners), 1 do
      local listener = self.listeners[j]
      local pathVariables = listener and self.get_path_variables(patches[i], listener);

      if (pathVariables ~= nil) then
        listener.callback({
          path = pathVariables,
          rawPath = patches[i].path,
          operation = patches[i].operation,
          value = patches[i].value
        })
        matched = true;
      end
    end

    -- check for fallback listener
    if (not matched and self.defaultListener) then
      self.defaultListener["callback"](patches[i])
    end

  end
end

function DeltaContainer:get_path_variables (patch, listener)
  -- skip if rules count differ from patch

  if table.getn(patch.path) ~= table.getn(listener.rules) then
    return false
  end

  local path = {}

  -- for (var i = 0, len = listener.rules.length; i < len; i++) {
  for i = table.getn(listener["rules"]), 1 do
    local matches = patch.path[i].match(listener.rules[i]);

    if (not matches or matches.length == 0 or matches.length > 2) then
      return false

    elseif (string.sub(listener.rawRules[i], 1, 2) == ":") then
      path[ string.sub(listener.rawRules[i], 2) ] = matches[1]
    end
  end

  return path
end

function DeltaContainer:reset ()
  self.listeners = {}
end

local function split(str,pat)
  local tbl={}
  str:gsub(pat,function(x) tbl[#tbl+1]=x end)
  return tbl
end

local function map(func, array)
  local new_array = {}
  for i,v in ipairs(array) do
    new_array[i] = func(v)
  end
  return new_array
end
