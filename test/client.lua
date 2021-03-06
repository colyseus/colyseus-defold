local Client = require('colyseus.client')

return function()
    describe("colyseus.client", function()
        it("join_or_create", function()
            async();

            local client = Client.new("")

            client:join_or_create("dummy", {}, function(err, room)
                print("ERROR!", err)
                assert_equal(err, true)
                done()
            end)

        end)
    end)
end