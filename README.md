<div align="center">
  <a href="https://github.com/colyseus/colyseus">
    <img src="https://github.com/colyseus/colyseus/blob/master/media/logo.svg?raw=true" width="40%" height="100" />
  </a>
  <br>
  <br>
  <a href="https://npmjs.com/package/colyseus">
    <img src="https://img.shields.io/npm/dm/colyseus.svg?style=for-the-badge&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAQAAAC1+jfqAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAAmJLR0QAAKqNIzIAAAAJcEhZcwAADsQAAA7EAZUrDhsAAAAHdElNRQfjAgETESWYxR33AAAAtElEQVQoz4WQMQrCQBRE38Z0QoTcwF4Qg1h4BO0sxGOk80iCtViksrIQRRBTewWxMI1mbELYjYu+4rPMDPtn12ChMT3gavb4US5Jym0tcBIta3oDHv4Gwmr7nC4QAxBrCdzM2q6XqUnm9m9r59h7Rc0n2pFv24k4ttGMUXW+sGELTJjSr7QDKuqLS6UKFChVWWuFkZw9Z2AAvAirKT+JTlppIRnd6XgaP4goefI2Shj++OnjB3tBmHYK8z9zAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDE5LTAyLTAxVDE4OjE3OjM3KzAxOjAwGQQixQAAACV0RVh0ZGF0ZTptb2RpZnkAMjAxOS0wMi0wMVQxODoxNzozNyswMTowMGhZmnkAAAAZdEVYdFNvZnR3YXJlAHd3dy5pbmtzY2FwZS5vcmeb7jwaAAAAAElFTkSuQmCC">
  </a>
  <a href="https://forum.colyseus.io/" title="Discuss on Forum">
    <img src="https://img.shields.io/badge/discuss-on%20forum-brightgreen.svg?style=for-the-badge&colorB=0069b8&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAQAAAC1+jfqAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAAmJLR0QAAKqNIzIAAAAJcEhZcwAADsQAAA7EAZUrDhsAAAAHdElNRQfjAgETDROxCNUzAAABB0lEQVQoz4WRvyvEARjGP193CnWRH+dHQmGwKZtFGcSmxHAL400GN95ktIpV2dzlLzDJgsGgGNRdDAzoQueS/PgY3HXHyT3T+/Y87/s89UANBKXBdoZo5J6L4K1K5ZxHfnjnlQUf3bKvkgy57a0r9hS3cXfMO1kWJMza++tj3Ac7/LY343x1NA9cNmYMwnSS/SP8JVFuSJmr44iFqvtmpjhmhBCrOOazCesq6H4P3bPBjFoIBydOk2bUA17I080Es+wSZ51B4DIA2zgjSpYcEe44Js01G0XjRcCU+y4ZMrDeLmfc9EnVd5M/o0VMeu6nJZxWJivLmhyw1WHTvrr2b4+2OFqra+ALwouTMDcqmjMAAAAldEVYdGRhdGU6Y3JlYXRlADIwMTktMDItMDFUMTg6MTM6MTkrMDE6MDAC9f6fAAAAJXRFWHRkYXRlOm1vZGlmeQAyMDE5LTAyLTAxVDE4OjEzOjE5KzAxOjAwc6hGIwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAAASUVORK5CYII=" alt="Discussion forum" />
  </a>
  <a href="https://discord.gg/RY8rRS7">
    <img src="https://img.shields.io/discord/525739117951320081.svg?style=for-the-badge&colorB=7581dc&logo=discord&logoColor=white">
  </a>
  <h3>
     Colyseus Multiplayer SDK for <a href="https://www.defold.com/">Defold Engine</a> <br/><a href="https://docs.colyseus.io/getting-started/defold">View documentation</a>
  </h3>
</div>

## Contributing

In order to start a test server for this project, do the following:

```
git clone https://github.com/colyseus/sdks-test-server
cd sdks-test-server
npm install
npm start
```

## Test suite

This project uses [deftest](https://github.com/britzl/deftest) for testing, the
assertion functions are documented by [@britzl](https://github.com/britzl) here: https://github.com/britzl/deftest#custom-asserts

Tests live in `test/` and are registered in `example/testsuite.script`. The
`auth` and `http` suites are commented out there because they need the test
server from [Contributing](#contributing); the rest run offline.

### From the editor

Open the project in Defold and run `example/testsuite.collection`. Results print
to the console.

### Headless

`make testsuite` builds the engine with `example/testsuite.collection` as the
bootstrap collection (`test/testsuite.ini` supplies that override) and runs it.
It exits non-zero when deftest reports a failure or an error, so it works as a
CI gate.

Two things are needed that Defold doesn't put on your `PATH`:

- **A `bob.jar` matching your editor.** Read `engine_sha1` from
  `/Applications/Defold.app/Contents/Resources/config`, then download
  `https://d.defold.com/archive/stable/<engine_sha1>/bob/bob.jar`.
- **A JDK 25 or newer.** The macOS editor bundles one, which the Makefile picks
  up from `Defold.app` by default.

```
make testsuite BOB=/path/to/bob.jar
```

`BOB`, `JAVA`, `DEFOLD_APP`, `PLATFORM` and `TEST_BUNDLE` are all overridable.
`PLATFORM` defaults to `arm64-macos` — use `x86_64-macos` on Intel, or
`x86_64-linux` on Linux.

### Known failures

As of 0.18 the suite reports 13 errors before you change anything:

- `PassiveSmoothing` and `ReckonValueAt` call `predict:track()` and
  `predict:track_reckon()`, which the declarative `attach(instance, config)`
  refactor removed.
- The `input` suite calls `assert_equal` from module-level helpers, outside the
  environment deftest injects assertions into.
- `MapSchemaTypes` and `Callbacks` fail inside `callbacks.lua`.

## Contributors

Big thanks to [Björn Ritzl](https://github.com/britzl). Without his efforts on
the WebSocket library this client wouldn't exist.

## License

MIT
