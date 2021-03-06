import { Schema, type, ArraySchema, MapSchema } from "@colyseus/schema";

export class Message extends Schema {
  @type("string") message: string;
}

export class Player extends Schema {
  @type("number") x: number;
  @type("number") y: number;

}

export class MyRoomState extends Schema {
  @type([Message]) messages = new ArraySchema<Message>();
  @type({ map: Player }) players = new MapSchema<Player>();
  @type("string") turn: string;
}