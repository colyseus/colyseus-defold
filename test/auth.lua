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

	describe("colyseus.auth", function()
		it("register_with_email_and_password", function()
			local client = Client.new("http://localhost:2567")
			local rand = math.floor(math.random(1, 2000))
			local email = "endel"..rand.."@colyseus.io"

			print("EMAIL??")
			print(email)

			local auth_data = async(function(done)
				client.auth:register_with_email_and_password(email, "123456", function(err, response)
					done(response)
				end)
			end)

			print("AUTH_DATA:")
			print(auth_data)
			print("client.auth.token =>")
			print(client.auth.token)

			assert_equal(auth_data.user.email, email)
			assert_equal(client.auth.token, auth_data.token)
		end)

		it("sign_in_with_email_and_password", function()
			assert_equal(true, false)
		end)

		it("sign_in_anonymously", function()
			assert_equal(true, false)
		end)

		it("sign_out", function()
			assert_equal(true, false)
		end)
	end)
end
