local Client = require('colyseus.client')
local callbacks = require('colyseus.serializer.schema.callbacks')

local M = {
	Client = Client,
	callbacks = callbacks
}

return M