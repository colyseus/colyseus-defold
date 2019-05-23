local utils = require "colyseus.utils"
local storage = require "colyseus.storage"

local auth = {}
auth.__index = auth

function auth.new (endpoint)
  local instance = EventEmitter:new({
    use_https = not sys.get_engine_info().is_debug,
    endpoint = endpoint:gsub("ws", "http"),
    http_timeout = 10,
    token = storage.get_item("token"),

    ping_interval = 20,
    ping_service_handle = nil
  })

  local is_emscripten = sys.get_sys_info().system_name == "HTML5"
  if is_emscripten then
    instance.use_https = html5.run("window['location']['protocol']") == "https:"
  end

  setmetatable(instance, auth)
  instance:init()
  return instance
end

--
-- PRIVATE METHODS
--

function auth:build_url(segments)
  local protocol = self.use_https and "https://" or "http://"
  return protocol .. self.endpoint .. segments
end

function auth:has_token()
  return self.token ~= nil and self.token ~= ""
end

function auth:get_platform_id()
  if info.system_name == "iPhone OS" then
    return "ios"

  else if info.system_name == "Android" then
    return "android"

  else if info.system_name == "HTML5" then
    return "html5"

  else if info.system_name == "Darwin" then
    return "osx"

  else if info.system_name == "Windows" then
    return "windows"

  else if info.system_name == "Linux" then
    return "linux"
  end
end

function auth:get_device_id()
  if get_platform_id() ~= nil then
		return info.device_ident
  else
		local unique_id = storage.get_item("device_id")
		if type(unique_id) ~= "string" then
      unique_id = tostring(math.random(0, 9999)) .. tostring(os.time(os.date("!*t")))
      storage.set_item("device_id", unique_id)
		end
		return unique_id
	end
end

function auth:request(method, segments, params, callback, headers)
  if not headers then headers = {} end

  local has_query_string = false
  local query_params = {}
  for k, v in pairs(params) do
    if v ~= nil then
      table.insert(query_params, k .. "=" .. utils.urlencode(tostring(v)))
      has_query_string = true
    end
  end

  if has_query_string then
    segments = segments .. "?" .. table.concat(query_params, "&")
  end

  local options = {}
  options['timeout'] = self.http_timeout

  http.request(build_url(segments), method, function(self, id, response)
		local data = response.response ~= '' and json.decode(response.response)
    local has_error = (response.status >= 400)
    local err = nil

    if has_error then
      err = (not data or next(data) == nil) and response.response or data.error
    end

    callback(err, data)
	end, headers, "", options)
end

function auth:login_request (query_params, success_cb)
  if self:has_token() then
    query_params['token'] = self.token
  end

  query_params['deviceId'] = get_device_id()
  query_params['platform'] = get_platform_id()

  request("POST", "/auth", query_params, function(err, response)
    if err then
      print("@colyseus/social: " .. tostring(err))
    else
      -- TODO: cache and check token expiration on every call
      -- response.expiresIn

      -- cache token locally
      storage.set_item("token", response.token)
      for field, value in pairs(response) do
        self[field] = value
      end

      -- initialize auto-ping
      self:register_ping_service()
    end

    success_cb(err, self)
  end)
end

--
-- PUBLIC METHODS
--

function auth:login(email_or_success_cb, optional_password, success_cb)
  local query_params = {}
  if not success_cb and not optional_password then
    success_cb = email_or_success_cb
  else
    query_params['email'] = email_or_success_cb
    query_params['password'] = optional_password
  end
  login_request(query_params, success_cb)
end

function auth:facebook_login(success_cb, permissions)
  if not facebook then
    error ("Facebook login is not supported on '" .. sys.get_sys_info().system_name .. "' platform")
  end

  facebook.login_with_read_permissions(permissions or { "public_profile", "email", "user_friends" }, function(self, data)
    if data.status == facebook.STATE_OPEN then
      login_request({ accessToken = facebook.access_token() }, success_cb)

    elseif data.status == facebook.STATE_CLOSED_LOGIN_FAILED then
      -- Do something to indicate that login failed
      print("@colyseus/social => FACEBOOK LOGIN FAILED")
    end

    -- An error occurred
    if data.error then
      print("@colyseus/social => FACEBOOK ERROR")
      pprint(data.error)
    end
  end)
end

function auth:register_ping_service()
  -- prevent from having more than one ping services
  if self.ping_service_handle ~= nil then
    self:unregister_ping_service()
  end
  self.ping_service_handle = timer.delay(self.ping_interval, true, function() self:ping() end)
end

function auth:unregister_ping_service()
  timer.cancel(self.ping_service_handle)
end

function auth:ping(success_cb)
  check_token()

  request("GET", "/auth", {}, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. self.token })
end

function auth:get_friend_requests(success_cb)
  check_token()

  request("GET", "/friends/requests", {}, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. self.token })
end

function auth:accept_friend_request(user_id, success_cb)
  check_token()

  request("PUT", "/friends/requests", { userId = user_id }, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. self.token })
end

function auth:decline_friend_request(user_id, success_cb)
  check_token()

  request("DELETE", "/friends/requests", { userId = user_id }, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. self.token })
end

function auth:send_friend_request(user_id, success_cb)
  check_token()

  request("POST", "/friends/requests", { userId = user_id }, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. self.token })
end

function auth:get_friends(success_cb)
  check_token()

  request("GET", "/friends/all", {}, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. self.token })
end

function auth:get_online_friends(success_cb)
  check_token()

  request("GET", "/friends/online", {}, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. self.token })
end

function auth:block_user(user_id, success_cb)
  check_token()

  request("POST", "/friends/block", { userId = user_id }, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. self.token })
end

function auth:unblock_user(user_id, success_cb)
  check_token()

  request("PUT", "/friends/block", { userId = user_id }, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. self.token })
end

function auth:logout()
  m.token = nil
end

return auth
