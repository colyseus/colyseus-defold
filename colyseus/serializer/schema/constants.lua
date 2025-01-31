local M = {}

-- START SPEC + OPERATION --
M.SPEC = {
    SWITCH_TO_STRUCTURE = 255,
    TYPE_ID = 213,
}

M.OPERATION = {
  -- ADD new structure/primitive
  ADD = 128,

  -- REPLACE structure/primitive
  REPLACE = 0,

  -- DELETE field
  DELETE = 64,

  -- DELETE field, followed by an ADD
  DELETE_AND_ADD = 192,

  -- Collection Operations
  CLEAR = 10,
}
-- END SPEC + OPERATION --

return M