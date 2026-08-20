# Changelog

All notable changes to the Colyseus Defold SDK are documented in this file.

## 0.17.5

- Fix `client:get_latency()` (and therefore `Client.select_by_latency()`) hanging on unresponsive endpoints. The measurement only resolved on a pong or a websocket `error`, so a server that closed the socket cleanly without replying (only a `close` event fires) left the callback pending forever, and a blackholed/unreachable host stalled indefinitely. `get_latency()` now also resolves on `close` and on a configurable `timeout` (seconds, default `1.5`, also forwarded through `select_by_latency()`), so a single wedged endpoint can no longer stall the whole selection. Ports the JS SDK fix for [#941](https://github.com/colyseus/colyseus/issues/941) — thanks @TJEvans for reporting!
- Fix `Client.select_by_latency()` being impossible to call: the module exported the constructor as a bare function (which Lua cannot index) and the function constructed clients via a non-callable internal table. The `Client` table is now callable, so both `Client(endpoint)` and `Client.select_by_latency(...)` work.
- Measure latency with `socket.gettime()` (millisecond resolution) instead of `os.time()`, which only had whole-second resolution and reported every endpoint as `0ms`.
