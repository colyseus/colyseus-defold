const http = require("http");
const express = require("express");

const colyseus = require("colyseus");
const ChatRoom = require('./chat_room');

const PORT = process.env.PORT || 2657;

process.on('unhandledRejection', r => console.log(r));

const app = new express();
const gameServer = new colyseus.Server({
  server: http.createServer(app)
});

// Register ChatRoom as "chat"
gameServer.register("chat", ChatRoom);

app.get("/something", function (req, res) {
    console.log("something!", process.pid);
    res.send("Hey!");
});

// Attach to port
gameServer.listen(PORT);

console.log("Listening on ws://localhost:" + PORT);
