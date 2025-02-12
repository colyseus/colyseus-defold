local Client = require('colyseus.client')

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
end