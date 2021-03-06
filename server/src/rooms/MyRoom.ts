import { Room, Client } from "colyseus";
import { Message, MyRoomState, Player } from "./schema/MyRoomState";

export class MyRoom extends Room<MyRoomState> {

  onCreate (options: any) {
    this.setState(new MyRoomState());

    // For "get_available_rooms" 
    this.setMetadata({
      bool: true,
      str: "string",
      int: 10,
      nested: { hello: "world" }
    });

    this.setSimulationInterval(() => this.update());

    this.clock.setInterval(() => {
      this.state.turn = "turn" + Math.random();
    }, 1000);

    this.onMessage("type1", (client: Client, message: any) => {
      console.log("Received type1 message =>", message)
    });

    this.onMessage(0, (client: Client, message: any) => {
      console.log("Received 0 message =>", message)
    });

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

  onJoin (client: Client, options: any) {
    console.log("client joined!", client.sessionId);

    this.state.players.set(client.sessionId, new Player().assign({ x: 0, y: 0 }));

    client.send("data", { hello: "world!" });

    const message = new Message("Schema-based message!");
    client.send(message);
  }

  onLeave (client: Client, consented: boolean) {
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
