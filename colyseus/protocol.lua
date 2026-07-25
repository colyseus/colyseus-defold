--
-- Protocol codes occupy bits 0..4 of the leading message byte (values 0..31).
-- Bits 5..7 carry modifier decorations OR'd onto the base code at send time.
-- Decoders strip the modifier bits before dispatching:
--
--     local code = bit.band(byte, protocol.CODE_MASK)
--     local modifiers = bit.band(byte, protocol.MODIFIER_MASK)
--
return {
  -- Room-related (10~18)
  JOIN_ROOM = 10,
  ERROR = 11,
  LEAVE_ROOM = 12,
  ROOM_DATA = 13,
  ROOM_STATE = 14,
  ROOM_STATE_PATCH = 15,
  ROOM_DATA_SCHEMA = 16, -- deprecated in 0.18 — never dispatched
  ROOM_DATA_BYTES = 17,
  PING = 18, -- ping/pong share this code (the server echoes it)

  -- Input-related (19~20) — consumed by the input layer (not ported yet)
  ROOM_INPUT_RELIABLE = 19,
  ROOM_INPUT_UNRELIABLE = 20,

  -- Request/response (21~22)
  ROOM_REQUEST = 21,  -- [byte, requestId varint, type(str|num), msgpack payload?]
  ROOM_RESPONSE = 22, -- [byte, requestId varint, status uint8, msgpack payload?]

  -- Isolates the base protocol code (low 5 bits, values 0..31).
  CODE_MASK = 0x1F,
  -- Isolates modifier bits (high 3 bits; only TIMED is assigned today).
  MODIFIER_MASK = 0xE0,
  -- A [uint32 sNow][uint32 inputSeq] prefix precedes the body — server time
  -- (ms since room start) + this client's last PROCESSED input seq. Set by
  -- the server on ROOM_STATE / ROOM_STATE_PATCH when the room uses
  -- define_input().
  MODIFIER_TIMED = 0x80,

  -- Status byte of a ROOM_RESPONSE reply.
  RESPONSE_STATUS = {
    OK = 0,
    REJECTED = 1, -- deliberate, typed rejection; the authored reason is the payload
    ERROR = 2,    -- handler fault (threw / no handler); payload is {name, message, code?}
  },

  -- Section tags for trailing tagged blobs in the JOIN_ROOM handshake:
  -- [tag byte][length varint][payload], repeated until end-of-buffer.
  -- Unknown tags are skipped via length (forward-compatible).
  HANDSHAKE_SECTION = {
    INPUT_REFLECTION = 1, -- reflection bytes for the room's input schema
    INPUT_OPTIONS = 2,    -- input feature flags + rates the client mirrors
  },

  CLOSE_CODE = {
    NORMAL_CLOSURE = 1000,
    GOING_AWAY = 1001,
    NO_STATUS_RECEIVED = 1005,
    ABNORMAL_CLOSURE = 1006,
    CONSENTED = 4000,
    SERVER_SHUTDOWN = 4001,
    WITH_ERROR = 4002,
    FAILED_TO_RECONNECT = 4003,
    MAY_TRY_RECONNECT = 4010,
  }
}
