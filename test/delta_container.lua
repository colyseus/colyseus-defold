local compare = require('colyseus.state_listener.compare')
local DeltaContainer = require('colyseus.state_listener.state_container')

function clone(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[clone(orig_key)] = clone(orig_value)
        end
        setmetatable(copy, clone(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function error_callback(change)
  error("shouldn't enter here")
end

return function()
  describe("fossil delta", function()
    local data
    local container
    local num_calls

    describe("state_container", function()

      before(function()
        num_calls = 0
        data = {
            players = {
                one = 1,
                two = 1
            },
            entity = {
                x = 0, y = 0, z = 0,
                xp = 100,
                rotation = 10
            },
            entities = {
                one = { x = 10, y = 0 },
                two = { x = 0, y = 0 },
            },
            chests = {
                one = { items = { one = 1, } },
                two = { items = { two = 1, } }
            },
            countdown = 10,
            sequence = { 0, 1, 2, 3, 4, 5 },
            board = {
                { 0, 1, 0, 4, 0 },
                { 6, 0, 3, 0, 0 },
            },
        }

        container = DeltaContainer.new(clone(data))
      end)

      it("should trigger callbacks for initial state", function()
          local container = DeltaContainer.new({})
          local callback = function (change)
            num_calls = num_calls + 1
          end

          container:listen("players", callback)
          container:listen("entity", callback)
          container:listen("entities/:id", callback)
          container:listen("chests/:id", callback)
          container:listen("chests/:id/items/:id", callback)
          container:listen("sequence/:number", callback)
          container:listen("board/:number/:number", callback)

          container:set(clone(data))
          assert_same(num_calls, 24)
      end)

      it("should listen to 'add' operation", function()
          container:listen("players", error_callback)
          container:listen("players/:string/:string", error_callback)
          container:listen("players/:string", function (change)
              assert_same(change.operation, "add")
              assert_same(change.raw_path, {"players", "three"})
              assert_same(change.path.string, "three")
              assert_same(change.value, 3)
          end)

          data.players.three = 3;
          container:set(data)
      end)

      it("should match the full path", function()
          container:listen(":name/x", function(change)
              assert_same(change.path.name, "entity")
              assert_same(change.value, 50)
          end);

          container:listen(":name/xp", function (change)
              assert_same(change.raw_path, {"entity", "xp"})
              assert_same(change.path.name, "entity")
              assert_same(change.value, 200)
          end);

          data.entity.x = 50
          data.entity.xp = 200

          container:set(data)
      end)

      it("should listen to 'remove' operation", function()
          container:listen("players/:name", function (change)
              assert_same(change.raw_path, { "players", "two" })
              assert_same(change.path.name, "two");
              assert_same(change.value, nil);
          end)

          data.players.two = nil
          container:set(data)
      end)

      it("should allow multiple callbacks for the same operation", function()
          local i = 0
          local accept = function(change) i = i + 1 end

          container:listen("players/:string/:string", error_callback)
          container:listen("players/:string", accept)
          container:listen("players/:string", accept)
          container:listen("players/:string", accept)

          data.players.three = 3
          container:set(data)

          assert_same(i, 3)
      end)

      it("should fill multiple variables on listen", function()
          container:listen("entities/:id/:attribute", function(change)
              if (change.path.id == "one") then
                  assert_same(change.path.attribute, "x")
                  assert_same(change.value, 20)

              elseif (change.path.id == "two") then
                  assert_same(change.path.attribute, "y")
                  assert_same(change.value, 40)
              end
          end)

          data.entities.one.x = 20
          data.entities.two.y = 40

          container:set(data)
      end)

      it("should create custom placeholder ", function()
          container:register_placeholder(":xyz", "([xyz])")

          container:listen("entity/:xyz", function(change)
              if (change.path.xyz == "x") then assert_same(change.value, 1)
              elseif (change.path.xyz == "y") then assert_same(change.value, 2)
              elseif (change.path.xyz == "z") then assert_same(change.value, 3)
              else error_callback() end
          end)

          data.entity.x = 1
          data.entity.y = 2
          data.entity.z = 3
          data.entity.rotation = 90

          container:set(data)
      end)

      it("should remove specific listener", function()
          container:listen("players/ten", function(change)
            assert_same(change.value.ten, 10)
          end)

          local listener = container:listen("players/ten", error_callback)
          container:remove_listener(listener)

          data.players.ten = { ten = 10 }
          container:set(data)
      end)

      it("using the same placeholder multiple times in the path", function()
          container:listen("chests/:id/items/:id", function(change)
              --
              -- TODO: the current implementation only populates the last ":id" into `change.path.id`
              --
              assert_same(change.path.id, "two")
              assert_same(change.value, 2)
          end)

          data.chests.one.items.two = 2
          container:set(data)
      end)

      it("should remove all listeners", function()
          container:listen("players", error_callback)
          container:listen("players", error_callback)
          container:listen("entity/:attribute", error_callback)
          container:remove_all_listeners()

          data.players['one'] = nil
          data.entity.x = 100
          data.players.ten = { ten = 10 }

          container:set(data)
      end)

      it("should trigger default listener as fallback", function()
          local numCallbacksExpected = 3
          local numCallbacks = 0

          container:listen("players/:string", function (change)
              if (change.operation == "add") then
                  assert_same(change.path.string, "three")
                  assert_same(change.value, 3)

              elseif (change.operation == "remove") then
                  assert_same(change.path.string, "two");
                  assert_same(change.value, nil);
              end
              numCallbacks = numCallbacks + 1
          end)

          container:listen(function (change)
              assert_same(change.path, { "entity", "rotation" })
              assert_same(change.operation, "replace")
              assert_same(change.value, 90)
              numCallbacks = numCallbacks + 1
          end)

          data.players.three = 3
          data.players.two = nil
          data.entity.rotation = 90

          container:set(data)
          assert_same(numCallbacks, numCallbacksExpected)
      end)

      it("should allow removing listeners inside a listener", function()
          -- local container = DeltaContainer.new({})
          -- local listener_to_remove = container:listen("entities/:id", function(change)
          --     container:remove_listener(listener_to_remove)
          --     num_calls = num_calls + 1
          -- end)
          --
          -- container:listen("players", function(change) num_calls = num_calls + 1 end)
          -- container:set(clone(data))
          --
          -- assert.are.same(num_calls, 2)
      end)

    end)
  end)
end
