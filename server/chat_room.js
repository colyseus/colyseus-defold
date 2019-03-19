var colyseus = require('colyseus');

class ChatRoom extends colyseus.Room {

  onInit (options) {
    this.setState({
      n: null,
      u: undefined,
      players: {},
      messages: [],
      turn: "none"
    });

    // for "get_available_rooms" (ROOM_LIST protocol)
    this.setMetadata({
      bool: true,
      str: "string",
      int: 10,
      nested: { hello: "world" }
    });

    this.setSimulationInterval( this.update.bind(this) );

    this.clock.setInterval(() => {
      this.state.turn = "turn" + Math.random()
    }, 1000);

    console.log("ChatRoom created!", options);
  }

  requestJoin (options) {
    console.log("request join!", options);
    return true;
  }

  onJoin (client) {
    console.log("client joined!", client.sessionId);
    this.state.players[client.sessionId] = { x: 0, y: 0 };
  }

  onLeave (client) {
    console.log("client left!", client.sessionId);
    delete this.state.players[client.sessionId];
  }

  onMessage (client, data) {
    console.log(data, "received from", client.sessionId);
    this.state.messages.push(client.sessionId + " sent " + data);
  }

  update () {
    for (var sessionId in this.state.players) {
      this.state.players[sessionId].x += 0.0001;
    }
  }

  onDispose () {
    console.log("Dispose ChatRoom");
  }

}

colyseus.serialize(colyseus.FossilDeltaSerializer)(ChatRoom);

module.exports = ChatRoom;
