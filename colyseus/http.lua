local JSON = require('colyseus.serializer.json')
local Connection = require('colyseus.connection')
local utils = require('colyseus.utils.utils')

---@class HTTP
---@field auth_token string
local HTTP = {}
HTTP.__index = HTTP

--- Every failure handed to a callback is one of these: `status` (0 when the
--- request never reached a server, otherwise the HTTP status) and `message`.
--- It concatenates and tostring()s to the message, so the documented
--- `print("ERROR: " .. err)` reads the same on every path.
---@class HTTPError
---@field status number
---@field message string
local HTTPError = {}
HTTPError.__index = HTTPError
HTTPError.__tostring = function(self) return self.message end
HTTPError.__concat = function(a, b)
  local function str(v) return (type(v) == "table" and v.message) or tostring(v) end
  return str(a) .. str(b)
end

local function http_error(status, message)
  return setmetatable({ status = status, message = message }, HTTPError)
end

---@param client Client
---@return HTTP
function HTTP.new (client)
  local instance = {}
  setmetatable(instance, HTTP)
  instance:init(client)
  return instance
end

---@private
function HTTP:init(client)
	self.client = client
end

---@param segments string
---@param options_or_callback table|fun(err:table, data:table)
---@param callback nil|fun(err:table, data:table)
function HTTP:get(segments, options_or_callback, callback)
  if type(options_or_callback) == "function" then
		callback = options_or_callback
		options_or_callback = {}
	elseif options_or_callback == nil then
		options_or_callback = {}
	end
	self:request("GET", segments, options_or_callback, callback)
end

---@param segments string
---@param options_or_callback table|fun(err:table, data:table)
---@param callback nil|fun(err:table, data:table)
function HTTP:post(segments, options_or_callback, callback)
  if type(options_or_callback) == "function" then
		callback = options_or_callback
		options_or_callback = {}
	elseif options_or_callback == nil then
		options_or_callback = {}
	end
	self:request("POST", segments, options_or_callback, callback)
end

---@param segments string
---@param options_or_callback table|fun(err:table, data:table)
---@param callback nil|fun(err:table, data:table)
function HTTP:put(segments, options_or_callback, callback)
  if type(options_or_callback) == "function" then
		callback = options_or_callback
		options_or_callback = {}
	elseif options_or_callback == nil then
		options_or_callback = {}
	end
	self:request("PUT", segments, options_or_callback, callback)
end

---@param segments string
---@param options_or_callback table|fun(err:table, data:table)
---@param callback nil|fun(err:table, data:table)
function HTTP:delete(segments, options_or_callback, callback)
  if type(options_or_callback) == "function" then
		callback = options_or_callback
		options_or_callback = {}
	elseif options_or_callback == nil then
		options_or_callback = {}
	end
	self:request("DELETE", segments, options_or_callback, callback)
end

---@private
function HTTP:_get_ws_endpoint(room, query_params)
  query_params = query_params or {}

  if self.auth_token ~= nil and self.auth_token ~= "" then
    query_params["_authToken"] = self.auth_token
  end

  local params = {}
  for k, v in pairs(query_params) do
    table.insert(params, k .. "=" .. tostring(v))
  end

  -- build request endpoint
  local protocol = (self.client.settings.use_ssl and "wss") or "ws"
  local port = ((self.client.settings.port ~= 80 and self.client.settings.port ~= 443) and ":" .. self.client.settings.port) or ""
  local public_address = (room ~= nil and room.publicAddress)
    or (self.client.settings.hostname .. port .. (self.client.settings.pathname or ""))

  if room ~= nil then
    return protocol .. "://" .. public_address .. "/" .. room.processId .. "/" .. room.roomId .. "?" .. table.concat(params, "&")
  else
    return protocol .. "://" .. public_address .. "/" .. "?" .. table.concat(params, "&")
  end
end

---@private
function HTTP:_get_http_endpoint(segments, query_params)
  query_params = query_params or {}

  local params = {}
  for k, v in pairs(query_params) do
    table.insert(params, k .. "=" .. tostring(v))
  end

  -- build request endpoint
  local protocol = (self.client.settings.use_ssl and "https") or "http"
  local port = ((self.client.settings.port ~= 80 and self.client.settings.port ~= 443) and ":" .. self.client.settings.port) or ""
  local public_address = self.client.settings.hostname .. port .. (self.client.settings.pathname or "")

  -- make sure segments start with "/"
  if string.sub(segments, 1, 1) ~= "/" then
    segments = "/" .. segments
  end

  local query = (#params > 0) and ("?" .. table.concat(params, "&")) or ""
  return protocol .. "://" .. public_address .. segments .. query
end

---@param method string
---@param segments string
---@param options table|fun(err:table, data:table)
---@param callback nil|fun(err:table, data:table)
function HTTP:request(method, segments, options, callback)
  if type(options) == "function" then
		callback = options
		options = {}
	elseif options == nil then
		options = {}
	end

  local headers = {
    ['Accept'] = 'application/json',
    ['Content-Type'] = 'application/json'
  }

	-- append headers
	for k, v in pairs(options.headers or {}) do
		headers[k] = v
	end

	if self.auth_token ~= nil and self.auth_token ~= "" then
		headers['Authorization'] = "Bearer " .. self.auth_token
	end

  local body = options.body and JSON.encode(options.body) or ""

  local url = self:_get_http_endpoint(segments)

  http.request(url, method, function(self, id, response)
    local data = response.response ~= '' and response.response
    local has_error = (response.status >= 400)
    local err = nil

    -- status 0: the request never reached a server. Name the URL — the usual
    -- cause is a dev server bound to ::1 only while this dials IPv4, and
    -- "offline" on its own sends people looking in the wrong place.
    if response.status == 0 then
      local detail = (response.error ~= nil and response.error ~= "")
        and (" (" .. response.error .. ")") or ""
      return callback(http_error(0, "offline: could not reach " .. url .. detail))
    end

    -- parse JSON response
    if response.headers['content-type'] and string.find(response.headers['content-type'], 'application/json') then
      data = json.decode(data)
    end

    -- an empty body leaves `data` false, so guard the index
    if has_error or (type(data) == "table" and data.error) then
      err = http_error(response.status,
        (type(data) == "table" and data.error) or response.error or response.response)
    end

    callback(err, data)
  end, headers, body, { timeout = Connection.config.connect_timeout })
end

return HTTP
