--
-- @colyseus/social is a Colyseus Pro ⚔️️🛡 feature.
--
-- Support Colyseus on Patreon to unlock access to it:
-- https://www.patreon.com/endel
--

local urlencode = require "colyseus.modules.urlencode"
local cache = require "colyseus.storage"

local m = {
  use_https = not sys.get_engine_info().is_debug,
  endpoint = "localhost:2567",
  http_timeout = 10,
  token = cache.get_item("token")
}

local is_emscripten = sys.get_sys_info().system_name == "HTML5"
if is_emscripten then
  m.use_https = html5.run("window['location']['protocol']") == "https:"
end

--
-- PRIVATE METHODS
--

local function build_url(segments)
  if not m.endpoint then
    error "'endpoint' must be set on 'colyseus.modules.social'"
  end

  local protocol = m.use_https and "https://" or "http://"
  return protocol .. m.endpoint .. segments
end

local function check_token()
  if m.token == nil or m.token == "" then
    error "missing token. call 'facebook_login' first."
  end
end

local function get_platform_id()
  if info.system_name == "iPhone OS" then
    return "ios"

  else if info.system_name == "Android" then
    return "android"

  else
    return nil
  end
end

local function get_device_id()
  if get_platform_id() ~= nil then
		return info.device_ident
  else
		local unique_id = cache.get_item("device_id")
		if type(unique_id) ~= "string" then
      unique_id = tostring(math.random(0, 9999)) .. tostring(os.time(os.date("!*t")))
      cache.set_item("device_id", unique_id)
		end
		return unique_id
	end
end

local function request(method, segments, params, callback, headers)
  if not headers then headers = {} end

  local has_query_string = false
  local query_string = {}
  for k, v in pairs(params) do
    if v ~= nil then
      table.insert(query_string, k .. "=" .. urlencode(tostring(v)))
      has_query_string = true
    end
  end

  if has_query_string then
    segments = segments .. "?" .. table.concat(query_string, "&")
  end

  local options = {}
  options['timeout'] = m.http_timeout

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

--
-- PUBLIC METHODS
--

function m.facebook_login(success_cb, permissions)
  if not facebook then
    error ("Facebook login is not supported on '" .. sys.get_sys_info().system_name .. "' platform")
  end

  facebook.login_with_read_permissions(permissions or { "public_profile", "email", "user_friends" }, function(self, data)
    if data.status == facebook.STATE_OPEN then

      -- TODO: get device id
      local query_params = {
        accessToken = facebook.access_token(),
        deviceId = get_device_id(),
        platform = get_platform_id()
      }

      request("GET", "/facebook", query_params, function(err, response)
        if err then error("@colyseus/social: " .. tostring(err)) end

        -- TODO: cache and check token expiration on every call
        -- response.expiresIn

        -- cache token locally
        cache.set_item("token", response.token)
        m.token = response.token

        success_cb(err, response)
      end)

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

function m.ping(success_cb)
  check_token()

  request("GET", "/ping", {}, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. m.token })
end


function m.get_friend_requests(success_cb)
  check_token()

  request("GET", "/friend_requests", {}, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. m.token })
end

function m.accept_friend_request(user_id, success_cb)
  check_token()

  request("PUT", "/friend_requests", { userId = user_id }, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. m.token })
end

function m.delete_friend_request(user_id, success_cb)
  check_token()

  request("DELETE", "/friend_requests", { userId = user_id }, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. m.token })
end

function m.send_friend_request(user_id, success_cb)
  check_token()

  request("POST", "/friend_requests", { userId = user_id }, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. m.token })
end

function m.get_friends(success_cb)
  check_token()

  request("GET", "/friends", {}, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. m.token })
end

function m.get_online_friends(success_cb)
  check_token()

  request("GET", "/online_friends", {}, function(err, response)
    if err then print("@colyseus/social: " .. tostring(err)) end
    success_cb(err, response)
  end, { authorization = "Bearer " .. m.token })
end

return m
