--
-- @colyseus/social has been deprecated.
-- you can manually require "colyseus.auth" if you still rely on it.
--
local utils = require "colyseus.utils.utils"
local storage = require "colyseus.storage"
local EventEmitter = require('colyseus.eventemitter')
local Connection = require('colyseus.connection')

local Auth = {}

Auth.__index = function (self, key)
  if key == "state" then
    return self.http.auth_token
  else
    return Auth[key]
  end
end

Auth.__newindex = function (self, key, value)
  if key == "token" then
    self.http.auth_token = value
  else
    rawset(self, key, value)
  end
end

function Auth.new (client)
  local instance = {
    client = client
  }
  setmetatable(instance, Auth)
  return instance
end

--
-- PUBLIC METHODS
--

function Auth:get_user_data(callback)
end

function Auth:register_with_email_and_password(email, password, options_or_callback, callback)
end

function Auth:sign_in_with_email_and_password(email, password, callback)
end

function Auth:sign_in_anonymously(options_or_callback, callback)
end

function Auth:send_password_reset_email(email, callback)
end

function Auth:sign_in_with_provider(provider_name, settings_or_callback, callback)
end

function Auth:sign_out()
end

return Auth
