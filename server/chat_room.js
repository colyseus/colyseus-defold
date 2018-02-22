var Room = require('colyseus').Room;

class ChatRoom extends Room {

  constructor () {
    super();

    this.setState({
      n: null,
      u: undefined,
      players: {},
      messages: [],
      turn: "none"
    });
  }

  onInit (options) {
    this.setSimulationInterval( this.update.bind(this) );

    this.clock.setInterval(() => {
      this.state.turn = "turn" + Math.random()
      console.log("Change turn:", this.state.turn);
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

module.exports = ChatRoom;
