var schema = require('@colyseus/schema');
var colyseus = require('colyseus');
var social = require('@colyseus/social');

class Message extends schema.Schema { }
schema.defineTypes(Message, {
  message: "string"
});

class Player extends schema.Schema { }
schema.defineTypes(Player, {
  x: "number",
  y: "number",
});

class State extends schema.Schema {
    constructor() {
        super();
        this.messages = new schema.ArraySchema(new Message("That's the first message."));
        this.players = new schema.MapSchema();
    }
}
schema.defineTypes(State, {
  messages: [Message],
  players: { map: Player },
  turn: "string"
});

class DemoRoom extends colyseus.Room {

  onCreate (options) {
    this.setState(new State());

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

    this.onMessage("type1", (client, message) => console.log("Received type1 message =>", message));
    this.onMessage(0, (client, message) => console.log("Received 0 message =>", message));

    this.onMessage("*", (client, type, message) => {
      this.broadcast("broadcast", { data: "something" });

      console.log(message, "received from", client.sessionId);
      this.state.messages.push(new Message().assign({
        message: client.sessionId + " sent " + message
      }));

      for (let message of this.state.messages) {
        message.message += "a";
      }
    });

    console.log("ChatRoom created!", options);
  }

  async onAuth(client, options) {
    // console.log("onAuth: ", options);
    return await social.User.findById(social.verifyToken(options.token)._id);
  }

  onJoin (client, options, user) {
    console.log("client joined!", client.sessionId);

    console.log("User:", user);
    this.state.players.set(client.sessionId, new Player().assign({ x: 0, y: 0 }));

    client.send("data", { hello: "world!" });

    const message = new Message("Schema-based message!");
    client.send(message);
  }

  onLeave (client) {
    console.log("client left!", client.sessionId);
    this.state.players.delete(client.sessionId);
  }

  update () {
    this.state.players.forEach((player) => {
      player.x += 0.0001;
    });
  }

  onDispose () {
    console.log("Dispose ChatRoom");
  }

}

module.exports = DemoRoom;
