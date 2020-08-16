local serializers = {
    ['none'] = require('colyseus.serialization.none'),
    ['fossil-delta'] = require('colyseus.serialization.fossil_delta'),
    ['schema'] = require('colyseus.serialization.schema'),
}

local exports = {}

exports.register_serializer = function(id, handler)
    serializers[id] = handler
end

exports.get_serializer = function(id)
    return serializers[id]
end

return exports