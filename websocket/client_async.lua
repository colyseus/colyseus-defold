local socket = require'socket.socket'
local sync = require'websocket.sync'
local tools = require'websocket.tools'

local new = function()
	local self = {}

	local emscripten = sys.get_sys_info().system_name == "HTML5"

	self.sock_connect = function(self, host, port)
		assert(coroutine.running(), "You must call the connect function from a coroutine")
		self.sock = socket.tcp()
		self.sock:settimeout(0)
		self.sock:connect(host,port)
		local sendt = { self.sock }
		-- start polling for successful connection or error
		while true do
			local receive_ready, send_ready, err = socket.select(nil, sendt, 0)
			if err == "timeout" then
				coroutine.yield()
			elseif err then
				self.sock:close()
				return nil, err
			elseif #send_ready == 1 then
				return true
			end
		end
	end

	self.sock_send = function(self, data, i, j)
		assert(coroutine.running(), "You must call the send function from a coroutine")
		local sent = 0
		i = i or 1
		j = j or #data
		while i < j do
			self.sock:settimeout(0)
			local bytes_sent, err = self.sock:send(data, i, j)
			if err == "timeout" then
				coroutine.yield()
			elseif err then
				return nil, err
			else
				coroutine.yield()
			end
			i = i + bytes_sent
			sent = sent + bytes_sent
		end
		return sent
	end

	self.sock_receive = function(self, pattern, prefix)
		assert(coroutine.running(), "You must call the receive function from a coroutine")
		prefix = prefix or ""
		local data, err
		repeat
			self.sock:settimeout(0)
			data, err, prefix = self.sock:receive(pattern, prefix)
			if err == "timeout" then
				coroutine.yield()
			end
		until data or (err and err ~= "timeout")
		return data, err, prefix
	end

	self.sock_close = function(self)
		self.sock:shutdown()
		self.sock:close()
	end

	self = sync.extend(self)

	local coroutines = {}

	local sync_connect = self.connect
	local sync_send = self.send
	local sync_receive = self.receive
	local sync_close = self.close

	local on_connected_fn
	local on_message_fn


	self.connect = function(...)
		local co = coroutine.create(function(self, ws_url, ws_protocol)
			if emscripten then
				local protocol, host, port, uri = tools.parse_url(ws_url)
				local ok, err = self.sock_connect(self, host .. uri, port)
				self.state = "OPEN"
				if on_connected_fn then on_connected_fn(ok, err) end
			else
				self.url = ws_url
				local err
				local ok, err_or_protocol, headers = sync_connect(self,ws_url,ws_protocol)
				if not ok then
					err = err_or_protocol
				end
				if on_connected_fn then on_connected_fn(ok, err) end
			end
		end)
		coroutines[co] = "connect"
		coroutine.resume(co, ...)
	end

	self.send = function(...)
		local co = coroutine.create(function(...)
			if emscripten then
				local bytes, err = self.sock_send(...)
				if err then
					print(err)
				end
			else
				local ok,was_clean,code,reason = sync_send(...)
				if not ok then
					print(reason)
				end
			end
		end)
		coroutines[co] = "send"
		coroutine.resume(co, ...)
	end

	self.receive = function(...)
		local co = coroutine.create(function(...)
			if emscripten then
				local data, sock_err = self.sock_receive(...)
				if on_message_fn then
					local ok, err = pcall(function() on_message_fn(data, sock_err) end)
					if not ok then
						print(err)
					end
				end
			else
				local message, opcode, was_clean, code, reason = sync_receive(...)
				if on_message_fn then
					local ok, err = pcall(function() on_message_fn(message, reason) end)
					if not ok then
						print(err)
					end
				end
			end
		end)
		coroutines[co] = "receive"
		coroutine.resume(co, ...)
	end

	self.close = function(...)
		if emscripten then
			self.sock_close(...)
			self.state = "CLOSED"
		else
			sync_close(...)
		end
	end


	self.step = function(self)
		for co,action in pairs(coroutines) do
			local status = coroutine.status(co)
			if status == "suspended" then
				coroutine.resume(co)
			elseif status == "dead" then
				coroutines[co] = nil
			end
		end
	end

	self.on_message = function(self, fn)
		on_message_fn = fn
		local co = coroutine.create(function()
			while true do
				if self.sock and self.state == "OPEN" then
					if emscripten then
						-- I haven't figured out how to know the length of the received data
						-- receiving with a pattern of "*a" or "*l" will block indefinitely
						-- A message is read as chunks of data at a time, concatenating it as
						-- it is received and repeated until an error
						local chunk_size = 1024
						local data, err, partial
						repeat
							self.sock:settimeout(0)
							local bytes_to_read = data and (#data + chunk_size) or chunk_size
							data, err, partial = self.sock:receive(bytes_to_read, data)
							if partial and partial ~= "" then
								data = partial
							end
							coroutine.yield()
						until err
						if data and on_message_fn then
							local ok, err = pcall(function() on_message_fn(data) end)
							if not ok then print(err) end
						end
					else
						local message, opcode, was_clean, code, reason = sync_receive(self)
						if message then
							local ok, err = pcall(function() on_message_fn(message) end)
							if not ok then print(err) end
						end
					end
				end
				coroutine.yield()
			end
		end)
		coroutines[co] = "on_message"
	end

	self.on_connected = function(self, fn)
		on_connected_fn = fn
	end

	return self
end

return new
