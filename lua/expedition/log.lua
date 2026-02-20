--- Append-only JSONL event log for expedition.nvim
local storage = require("expedition.storage")
local types = require("expedition.types")

local M = {}

--- Get the log file path for an expedition.
--- @param expedition_id expedition.ExpeditionId
--- @return string
function M.log_path(expedition_id)
  local root = storage.project_root()
  local pid = storage.project_id(root)
  return storage.ensure_expedition_dir(pid, expedition_id) .. "/log.jsonl"
end

--- Append a log entry for an expedition.
--- @param expedition_id expedition.ExpeditionId
--- @param event string
--- @param data table?
--- @return boolean
function M.append(expedition_id, event, data)
  local config = require("expedition.config")
  if not config.val("log.enabled") then
    return true
  end
  local entry = types.new_log_entry(event, expedition_id, data or {})
  local path = M.log_path(expedition_id)
  return storage.append_jsonl(path, entry)
end

--- Read all log entries for an expedition.
--- @param expedition_id expedition.ExpeditionId
--- @return expedition.LogEntry[]
function M.read(expedition_id)
  local path = M.log_path(expedition_id)
  return storage.read_jsonl(path)
end

--- Read the last n log entries for an expedition.
--- @param expedition_id expedition.ExpeditionId
--- @param n number
--- @return expedition.LogEntry[]
function M.tail(expedition_id, n)
  local entries = M.read(expedition_id)
  if #entries <= n then
    return entries
  end
  local result = {}
  for i = #entries - n + 1, #entries do
    table.insert(result, entries[i])
  end
  return result
end

return M
