# Changelog

All notable changes to the Colyseus Defold SDK are documented in this file.

## 0.18.1

- `room:leave()` called again before the first leave completes is now a no-op;
  it used to throw "Connection isn't connected". A send that races the socket
  closing no longer throws either.
- `room:input({ mode = "unreliable" })` now works: it sends over the WebSocket,
  the same fallback the JS SDK uses when there is no datagram channel. It used
  to raise an error.
- MapSchema has `get(key)` and `has(key)`. `map[key]` returns the method for
  keys such as `"keys"`, `"length"` or `"items"`.
- ArraySchema `each()` and `index_of()` now go in index order, and `length()`
  no longer walks the whole array.
- Predicted `float32` fields keep negative values — the reconciler's float32
  rounding returned them positive. Halfway values now round to even, like the
  server.
- `ctx:memo()` replays a memoized `false` as `false` (it came back `nil`).
- MessagePack floats smaller than ~2.2e-308 (~1.2e-38 for float32) now decode
  correctly, and are no longer flushed to zero when encoded.
- `require "colyseus.client"` now works outside the Defold engine.
- For a `localhost` endpoint, the unreachable-server error now says Defold
  dials IPv4, which points at dev servers that listen on `::1` only.

## 0.18.0

- **Breaking:** a failed matchmaking call now always hands the callback a table
  with `status` and `message`. It previously passed the bare string `"offline"`
  when the server could not be reached, so `err.message` was nil on the one path
  a first-run user is most likely to hit. Code testing `err == "offline"` should
  test `err.status == 0` instead; `err.message` and `"..." .. err` work on every
  path.
- The unreachable-server message now names the URL that was dialled, and folds
  in the platform's own error where there is one. A dev server bound to `::1`
  only (the default for `vite`, `next dev`, and others) while the SDK dials IPv4
  used to report just `offline`.
- `t.quantized()` fields on a range symmetric about zero (`min = -1, max = 1`) now
  decode an exact `0`. A released input axis or a resting velocity arrived as one
  quantum above zero, so an `== 0` check never fired and anything integrating the
  value drifted. Requires a server on @colyseus/schema 5.0.27 — the wire mapping
  for these fields changed.

## 0.17.5

- Fix `client:get_latency()` (and therefore `Client.select_by_latency()`) hanging on unresponsive endpoints. The measurement only resolved on a pong or a websocket `error`, so a server that closed the socket cleanly without replying (only a `close` event fires) left the callback pending forever, and a blackholed/unreachable host stalled indefinitely. `get_latency()` now also resolves on `close` and on a configurable `timeout` (seconds, default `1.5`, also forwarded through `select_by_latency()`), so a single wedged endpoint can no longer stall the whole selection. Ports the JS SDK fix for [#941](https://github.com/colyseus/colyseus/issues/941) — thanks @TJEvans for reporting!
- Fix `Client.select_by_latency()` being impossible to call: the module exported the constructor as a bare function (which Lua cannot index) and the function constructed clients via a non-callable internal table. The `Client` table is now callable, so both `Client(endpoint)` and `Client.select_by_latency(...)` work.
- Measure latency with `socket.gettime()` (millisecond resolution) instead of `os.time()`, which only had whole-second resolution and reported every endpoint as `0ms`.
