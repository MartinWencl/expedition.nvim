--- Summit condition CRUD for expedition.nvim
local types = require("expedition.types")
local storage = require("expedition.storage")
local hooks = require("expedition.hooks")
local log = require("expedition.log")
local expedition_mod = require("expedition.expedition")

local M = {}

local VALID_STATUSES = { open = true, met = true, abandoned = true }

--- Get the path to the conditions.json for the active expedition.
--- @return string?
function M.conditions_path()
  local active = expedition_mod.get_active()
  if not active then return nil end
  return expedition_mod.expedition_dir(active.id) .. "/conditions.json"
end

--- Read all conditions from disk for the active expedition.
--- @return expedition.SummitCondition[]
local function read_conditions()
  local path = M.conditions_path()
  if not path then return {} end
  return storage.read_json(path) or {}
end

--- Write all conditions to disk for the active expedition.
--- @param conditions expedition.SummitCondition[]
--- @return boolean
local function write_conditions(conditions)
  local path = M.conditions_path()
  if not path then return false end
  return storage.write_json(path, conditions)
end

--- Create a new summit condition in the active expedition.
--- @param text string
--- @return expedition.SummitCondition?
function M.create(text)
  local active = expedition_mod.get_active()
  if not active then
    vim.notify("[expedition] no active expedition", vim.log.levels.ERROR)
    return nil
  end

  local condition = types.new_summit_condition(text)
  local conditions = read_conditions()
  table.insert(conditions, condition)
  write_conditions(conditions)

  log.append(active.id, "condition.created", { condition_id = condition.id, text = text })
  hooks.dispatch("condition.created", { condition = condition })

  return condition
end

--- List all conditions for the active expedition.
--- @return expedition.SummitCondition[]
function M.list()
  return read_conditions()
end

--- Get a condition by ID.
--- @param id expedition.ConditionId
--- @return expedition.SummitCondition?
function M.get(id)
  local conditions = read_conditions()
  for _, c in ipairs(conditions) do
    if c.id == id then
      return c
    end
  end
  return nil
end

--- Update a condition's fields.
--- @param id expedition.ConditionId
--- @param changes table
--- @return expedition.SummitCondition?
function M.update(id, changes)
  local active = expedition_mod.get_active()
  if not active then return nil end

  local util = require("expedition.util")
  local conditions = read_conditions()
  for i, c in ipairs(conditions) do
    if c.id == id then
      for k, v in pairs(changes) do
        c[k] = v
      end
      c.updated_at = util.timestamp()
      conditions[i] = c
      write_conditions(conditions)

      log.append(active.id, "condition.updated", { condition_id = id, changes = changes })
      hooks.dispatch("condition.updated", { condition = c, changes = changes })
      return c
    end
  end
  return nil
end

--- Delete a condition by ID.
--- @param id expedition.ConditionId
--- @return boolean
function M.delete(id)
  local active = expedition_mod.get_active()
  if not active then return false end

  local conditions = read_conditions()
  for i, c in ipairs(conditions) do
    if c.id == id then
      table.remove(conditions, i)
      write_conditions(conditions)

      log.append(active.id, "condition.deleted", { condition_id = id })
      hooks.dispatch("condition.deleted", { condition_id = id })
      return true
    end
  end
  return false
end

--- Set a condition's status.
--- @param id expedition.ConditionId
--- @param status "open"|"met"|"abandoned"
--- @return expedition.SummitCondition?
function M.set_status(id, status)
  if not VALID_STATUSES[status] then
    vim.notify("[expedition] invalid condition status: " .. tostring(status), vim.log.levels.ERROR)
    return nil
  end

  local active = expedition_mod.get_active()
  if not active then return nil end

  local util = require("expedition.util")
  local conditions = read_conditions()
  for i, c in ipairs(conditions) do
    if c.id == id then
      local from = c.status
      c.status = status
      c.updated_at = util.timestamp()
      conditions[i] = c
      write_conditions(conditions)

      log.append(active.id, "condition.status_changed", { condition_id = id, from = from, to = status })
      hooks.dispatch("condition.status_changed", { condition = c, from = from, to = status })
      return c
    end
  end
  return nil
end

return M
