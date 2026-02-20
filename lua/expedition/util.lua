--- Pure utility functions for expedition.nvim
--- No dependencies on other expedition modules.
local M = {}

--- Generate a unique ID (8 hex chars: timestamp-based + random suffix).
--- @return string
function M.id()
  local t = os.time()
  local r = math.random(0, 0xFFFF)
  return string.format("%04x%04x", t % 0x10000, r)
end

--- Return current time as ISO 8601 string.
--- @return expedition.Timestamp
function M.timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

--- XOR two 32-bit integers using arithmetic (Lua 5.1 compatible).
--- @param a number
--- @param b number
--- @return number
local function bxor(a, b)
  local result = 0
  local bit_val = 1
  for _ = 1, 32 do
    local a_bit = a % 2
    local b_bit = b % 2
    if a_bit ~= b_bit then
      result = result + bit_val
    end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    bit_val = bit_val * 2
  end
  return result
end

--- FNV-1a 32-bit hash (Lua 5.1 compatible, no bit module).
--- @param str string
--- @return string 8 hex chars
function M.hash(str)
  local h = 2166136261
  for i = 1, #str do
    h = (bxor(h, str:byte(i)) * 16777619) % 0x100000000
  end
  return string.format("%08x", h)
end

--- Hash an array of lines.
--- @param lines string[]
--- @return string
function M.hash_lines(lines)
  return M.hash(table.concat(lines, "\n"))
end

--- Clamp a number between min and max.
--- @param n number
--- @param min number
--- @param max number
--- @return number
function M.clamp(n, min, max)
  if n < min then return min end
  if n > max then return max end
  return n
end

--- Shallow copy a table.
--- @param t table
--- @return table
function M.shallow_copy(t)
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = v
  end
  return copy
end

return M
