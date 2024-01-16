local Client = require('colyseus.client')

return function()
    describe("colyseus.http", function()
        it("assert", function()
            local client = Client.new("http://localhost:2567")
            assert_equal(true, true);
        end)
    end)
end