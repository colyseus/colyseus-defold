-- Use codes between 0~127 for lesser throughput (1 byte)

return {
  -- User-related (0~8)
  USER_ID = 1,

  -- Room-related (9~19)
  JOIN_REQUEST = 9,
  JOIN_ROOM = 10,
  ERROR = 11,
  LEAVE_ROOM = 12,
  ROOM_DATA = 13,
  ROOM_STATE = 14,
  ROOM_STATE_PATCH = 15,

  ROOM_DATA_SCHEMA = 16,

  -- Match-making related (20~29)
  ROOM_LIST = 20,

  -- Generic messages (50~60)
  BAD_REQUEST = 50
}
