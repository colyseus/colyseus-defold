local Client = require('colyseus.client')

local unpack = _G.unpack or table.unpack

-- Helper function to handle asynchronous operations with coroutines
function async(fn, ...)
	assert(fn)
	local co = coroutine.running()
	assert(co)
	local results = nil
	local state = "RUNNING"
	fn(function(...)
		results = { ... }
		if state == "YIELDED" then
			coroutine.resume(co)
		else
			state = "DONE"
		end
	end, ...)
	if state == "RUNNING" then
		state = "YIELDED"
		coroutine.yield()
		state = "DONE"		-- not really needed
	end
	return unpack(results)
end

return function()
	math.randomseed(os.time())
	local endpoint = "http://localhost:2567"

	describe("colyseus.auth", function()
		it("register_with_email_and_password", function()
			local client = Client.new(endpoint)
			local rand = math.floor(math.random(1, 999999))
			local email = "endel"..rand.."@colyseus.io"

			local auth_data = async(function(done)
				client.auth:register_with_email_and_password(email, "123456", function(err, response)
					done(response)
				end)
			end)

			assert_equal(auth_data.user.email, email)
			assert_equal(client.auth.token, auth_data.token)
		end)

		it("sign_in_with_email_and_password", function()
			local client = Client.new(endpoint)

			local rand = math.floor(math.random(1, 999999))
			local email = "endel"..rand.."@colyseus.io"
			local password = "123456"

			-- register user first
			async(function(done)
				client.auth:register_with_email_and_password(email, password, function(err, response)
					done(response)
				end)
			end)
			-- clear token
			client.auth:sign_out()

			local onchange_token = nil
			local onchange_user = nil

			client.auth:on_change(function(auth_data)
				onchange_token = auth_data.token
				onchange_user = auth_data.user
			end)

			local auth_data = async(function(done)
				client.auth:sign_in_with_email_and_password(email, password, function(err, response)
					done(response)
				end)
			end)

			assert_equal(auth_data.user.email, email)
			assert_equal(client.auth.token, auth_data.token)

			assert_equal(onchange_user.email, email)
			assert_equal(onchange_token, auth_data.token)
		end)

		it("sign_in_anonymously", function()
			local client = Client.new(endpoint)

			local auth_data = async(function(done)
				client.auth:sign_in_anonymously({ custom_data = "hello" }, function(err, response)
					done(response)
				end)
			end)

			assert_equal(auth_data.user.custom_data, "hello")
			assert_equal(auth_data.user.anonymous, true)
			assert_not_nil(auth_data.user.anonymousId)
			assert_equal(client.auth.token, auth_data.token)
		end)

		it("sign_out", function()
			local on_change_call_count = 0

			local client = Client.new(endpoint)

			client.auth:on_change(function(auth_data)
				on_change_call_count = on_change_call_count + 1
			end)

			async(function(done)
				client.auth:sign_in_anonymously({ custom_data = "hello" }, function(err, response)
					done(response)
				end)
			end)

			assert_not_nil(client.auth.token)

			client.auth:sign_out()

			assert_equal(on_change_call_count, 3)
			assert_equal(client.auth.token, nil)

		end)
	end)
end
