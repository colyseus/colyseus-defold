local utils = require "colyseus.utils"
local storage = require "colyseus.storage"
local EventEmitter = require('colyseus.eventemitter')

local Push = {}
Push.__index = Push

function Push.new (endpoint)
  local instance = EventEmitter:new({
    endpoint = endpoint:gsub("ws", "http"),
  })

  setmetatable(instance, Push)
  return instance
end

function Push:register()
  local system_name = sys.get_sys_info().system_name
  if system_name == "HTML5" then
    -- run webpush register script
    html5.run(self:_webpush_register_script())

  elseif system_name == "iPhone OS" or system_name == "Android" then
    -- register for iOS / Android

    push.register({}, function(self, token, error)
      -- send "token" to backend service
    end)
  end
end

function Push:_webpush_register_script()
 return [[
const check = () => {
  if (!("serviceWorker" in navigator)) {
    throw new Error("No Service Worker support!");
  }
  if (!("PushManager" in window)) {
    throw new Error("No Push API Support!");
  }
};

const registerServiceWorker = async () => {
  try {
    return await navigator.serviceWorker.register("]] .. self.endpoint .. "/push" .. [[");

  } catch(e) {
    console.error(e);
    console.error(e.message);
  }
};

const requestNotificationPermission = async () => {
  const permission = await window.Notification.requestPermission();
  // value of permission can be 'granted', 'default', 'denied'
  // granted: user has accepted the request
  // default: user has dismissed the notification permission popup by clicking on x
  // denied: user has denied the request.
  if (permission !== "granted") {
    throw new Error("Permission not granted for Notification");
  }
};

const main = async () => {
  check();
  await registerServiceWorker();
  await requestNotificationPermission();
};
main();
]]
end

return Push