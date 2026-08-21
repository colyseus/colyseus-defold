local Client = require('colyseus.client')
local vendored_json = require('colyseus.serializer.json')

--- Drive HTTP:request without a server: swap the engine's `http` global for a
--- stub that answers with `response` verbatim. Returns whatever the SDK handed
--- the callback, plus the URL it dialled.
local function with_response(client, response, call)
  local original_http, original_json = http, json
  local dialled
  _G.http = {
    request = function(url, _method, callback, _headers, _body, _options)
      dialled = url
      callback(nil, 1, response)
    end,
  }
  _G.json = vendored_json
  local ok, err = pcall(call)
  _G.http, _G.json = original_http, original_json
  if not ok then error(err, 0) end
  return dialled
end

return function()
    describe("colyseus.client", function()
        it("init protocol with port", function()
            local client = Client("http://localhost:2567")
            assert_equal(client.settings.hostname, "localhost");
            assert_equal(client.settings.port, 2567);

            local client = Client("ws://localhost:2567")
            assert_equal(client.settings.hostname, "localhost");
            assert_equal(client.settings.port, 2567);
        end)

        it("init protocol without port", function()
            local client = Client("http://localhost")
            assert_equal(client.settings.hostname, "localhost");
            assert_equal(client.settings.port, 80);

            local client = Client("ws://localhost")
            assert_equal(client.settings.hostname, "localhost");
            assert_equal(client.settings.port, 80);
        end)

        it("init secure protocol with port", function()
            local client = Client("https://localhost:2567")
            assert_equal(client.settings.hostname, "localhost");
            assert_equal(client.settings.port, 2567);

            local client = Client("wss://localhost:2567")
            assert_equal(client.settings.hostname, "localhost");
            assert_equal(client.settings.port, 2567);
        end)

        it("init secure protocol without port", function()
            local client = Client("https://localhost")
            assert_equal(client.settings.hostname, "localhost");
            assert_equal(client.settings.port, 443);

            local client = Client("wss://localhost")
            assert_equal(client.settings.hostname, "localhost");
            assert_equal(client.settings.port, 443);
        end)

        it("init with settings", function()
            local client = Client({
                hostname = "localhost",
                port = 443
            })
            assert_equal(client.settings.hostname, "localhost");
            assert_equal(client.settings.port, 443);

            local client = Client({
                hostname = "192.168.1.10",
                port = 80
            })
            assert_equal(client.settings.hostname, "192.168.1.10");
            assert_equal(client.settings.port, 80);
        end)
    end)

    describe("colyseus.client matchmaking errors", function()

        --- status 0 used to hand back the bare string "offline", so err.message
        --- was nil on the one path a first-run user is most likely to hit.
        it("unreachable server reports a table naming the url", function()
            local client = Client("http://127.0.0.1:5173")
            local err
            local url = with_response(client, { status = 0, response = "", headers = {} }, function()
                client.http:request('POST', "matchmake/joinOrCreate/air_hockey", {}, function(e) err = e end)
            end)

            assert_equal("table", type(err))
            assert_equal(0, err.status)
            assert_not_nil(string.find(err.message, url, 1, true))
            assert_equal("http://127.0.0.1:5173/matchmake/joinOrCreate/air_hockey", url)
            -- the documented example concatenates the error straight into a print
            assert_equal("JOIN ERROR: " .. err.message, "JOIN ERROR: " .. err)
            assert_equal(err.message, tostring(err))
        end)

        it("unreachable server folds in the platform's own error", function()
            local client = Client("http://127.0.0.1:5173")
            local err
            with_response(client, { status = 0, response = "", headers = {},
                                    error = "connection refused" }, function()
                client.http:request('POST', "matchmake/joinOrCreate/x", {}, function(e) err = e end)
            end)
            assert_not_nil(string.find(err.message, "connection refused", 1, true))
        end)

        it("http error surfaces the server's message, same shape", function()
            local client = Client("http://localhost:2567")
            local err
            with_response(client, {
                status = 400,
                response = '{"error":"room nope not defined"}',
                headers = { ["content-type"] = "application/json" },
            }, function()
                client.http:request('POST', "matchmake/join/nope", {}, function(e) err = e end)
            end)

            assert_equal("table", type(err))
            assert_equal(400, err.status)
            assert_equal("room nope not defined", err.message)
            assert_equal("JOIN ERROR: room nope not defined", "JOIN ERROR: " .. err)
        end)

        --- an empty body leaves the decoded value false, which used to be
        --- indexed for `.error`
        it("empty 200 body is not an error", function()
            local client = Client("http://localhost:2567")
            local err, called = nil, false
            with_response(client, { status = 200, response = "", headers = {} }, function()
                client.http:request('POST', "matchmake/join/x", {}, function(e)
                    called = true
                    err = e
                end)
            end)
            assert_true(called)
            assert_nil(err)
        end)

        it("join_or_create forwards the error unchanged", function()
            local client = Client("http://127.0.0.1:5173")
            local err
            with_response(client, { status = 0, response = "", headers = {} }, function()
                client:join_or_create("air_hockey", {}, function(e) err = e end)
            end)
            assert_equal(0, err.status)
            assert_not_nil(string.find(err.message, "offline", 1, true))
        end)

    end)
end