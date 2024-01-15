local JSON = require('colyseus.serialization.json')
local Connection = require('colyseus.connection')
local utils = require('colyseus.utils.utils')

---@class HTTP
---@field auth_token string
local HTTP = {}
HTTP.__index = HTTP

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

function HTTP:get(segments, options_or_callback, callback)
  if type(options_or_callback) == "function" then
		callback = options_or_callback
		options_or_callback = {}
	elseif options_or_callback == nil then
		options_or_callback = {}
	end
	self:request("GET", segments, options_or_callback, callback)
end

function HTTP:post(segments, options_or_callback, callback)
  if type(options_or_callback) == "function" then
		callback = options_or_callback
		options_or_callback = {}
	elseif options_or_callback == nil then
		options_or_callback = {}
	end
	self:request("POST", segments, options_or_callback, callback)
end

function HTTP:put(segments, options_or_callback, callback)
  if type(options_or_callback) == "function" then
		callback = options_or_callback
		options_or_callback = {}
	elseif options_or_callback == nil then
		options_or_callback = {}
	end
	self:request("PUT", segments, options_or_callback, callback)
end

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

  local params = {}
  for k, v in pairs(query_params) do
    table.insert(params, k .. "=" .. tostring(v))
  end

  -- build request endpoint
  local protocol = (self.client.settings.use_ssl and "wss") or "ws"
  local port = ((self.client.settings.port ~= 80 and self.client.settings.port ~= 443) and ":" .. self.client.settings.port) or ""
  local public_address = (room.publicAddress) or self.client.settings.hostname .. port

  return protocol .. "://" .. public_address .. "/" .. room.processId .. "/" .. room.roomId .. "?" .. table.concat(params, "&")
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
  local public_address = self.client.settings.hostname .. port

  -- make sure segments start with "/"
  if string.sub(segments, 1, 1) ~= "/" then
    segments = "/" .. segments
  end

  return protocol .. "://" .. public_address .. segments .. "?" .. table.concat(params, "&")
end

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

  local body = options.body and JSON.encode(options.body) or ""

  http.request(self:_get_http_endpoint(segments), method, function(self, id, response)
    local data = response.response ~= '' and response.response
    local has_error = (response.status >= 400)
    local err = nil

    -- parse JSON response
    if response.headers['content-type'] and string.find(response.headers['content-type'], 'application/json') then
      data = json.decode(data)
    end

    if not data and response.status == 0 then
      return callback("offline")
    end

    if has_error or data.error then
      err = {
        status = response.status,
        message = (data and data.error) or response.error or response.response
      }
    end

    callback(err, data)
  end, headers, body, { timeout = Connection.config.connect_timeout })
end

return HTTP
