const http = require("http");
const express = require("express");
const cors = require("cors");

const colyseus = require("colyseus");
const socialRoutes = require("@colyseus/social/express").default;
const DemoRoom = require('./demo_room');

const PORT = process.env.PORT || 2567;

process.on('unhandledRejection', r => console.log(r));

const app = new express();

// allow CORS
app.use(cors());
app.use(express.json());

const gameServer = new colyseus.Server({
  server: http.createServer(app),
  express: app
});

// bind @colyseus/social
app.use("/", socialRoutes);

// Register ChatRoom as "chat"
gameServer.define("demo", DemoRoom);

app.get("/something", function (req, res) {
    console.log("something!", process.pid);
    res.send("Hey!");
});

// Attach to port
gameServer.listen(PORT);

console.log("Listening on ws://localhost:" + PORT);
