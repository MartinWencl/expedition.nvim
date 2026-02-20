--- Expedition CRUD and active state management
local types = require("expedition.types")
local storage = require("expedition.storage")
local hooks = require("expedition.hooks")
local log = require("expedition.log")

local M = {}

--- @type expedition.Expedition?
local _active = nil

--- Get the project ID for the current project.
--- @return expedition.ProjectId project_id
--- @return string root
local function project_info()
  local root = storage.project_root()
  local pid = storage.project_id(root)
  return pid, root
end

--- Get the directory for an expedition.
--- @param expedition_id expedition.ExpeditionId
--- @return string
function M.expedition_dir(expedition_id)
  local pid = project_info()
  return storage.ensure_expedition_dir(pid, expedition_id)
end

--- Create a new expedition, persist it, set as active, log and dispatch.
--- @param name string
--- @param opts table?
--- @return expedition.Expedition
function M.create(name, opts)
  local pid, root = project_info()
  storage.write_project_meta(pid, root)

  local exp = types.new_expedition(name, opts)
  local dir = storage.ensure_expedition_dir(pid, exp.id)

  -- Persist expedition
  storage.write_json(dir .. "/expedition.json", exp)
  -- Initialize empty notes
  storage.write_json(dir .. "/notes.json", {})
  -- Initialize empty route (Phase 2 stub)
  storage.write_json(dir .. "/route.json", {})
  -- Initialize empty conditions
  storage.write_json(dir .. "/conditions.json", {})
  -- Initialize empty branches and breadcrumbs (Phase 4)
  storage.write_json(dir .. "/branches.json", {})
  storage.write_json(dir .. "/breadcrumbs.json", {})

  -- Set active
  M.set_active(exp)

  -- Log and dispatch
  log.append(exp.id, "expedition.created", { name = name })
  hooks.dispatch("expedition.created", { expedition = exp })

  return exp
end

--- List all expeditions for the current project.
--- @return expedition.ExpeditionSummary[]
function M.list()
  local pid = project_info()
  local project_dir = storage.ensure_project_dir(pid)
  local exp_dir = project_dir .. "/expeditions"
  local dirs = storage.list_dirs(exp_dir)

  local summaries = {}
  for _, dir_name in ipairs(dirs) do
    local path = exp_dir .. "/" .. dir_name .. "/expedition.json"
    local data = storage.read_json(path)
    if data then
      local notes_path = exp_dir .. "/" .. dir_name .. "/notes.json"
      local notes = storage.read_json(notes_path) or {}
      table.insert(summaries, {
        id = data.id,
        name = data.name,
        status = data.status,
        created_at = data.created_at,
        note_count = #notes,
      })
    end
  end

  return summaries
end

--- List all expedition names (for command completion).
--- @return string[]
function M.list_names()
  local summaries = M.list()
  local names = {}
  for _, s in ipairs(summaries) do
    table.insert(names, s.name)
  end
  return names
end

--- Load an expedition by ID and set it as active.
--- @param id expedition.ExpeditionId
--- @return expedition.Expedition?
function M.load(id)
  local pid = project_info()
  local dir = storage.ensure_expedition_dir(pid, id)
  local data, err = storage.read_json(dir .. "/expedition.json")
  if not data then
    vim.notify("[expedition] failed to load: " .. tostring(err), vim.log.levels.ERROR)
    return nil
  end
  M.set_active(data)
  return data
end

--- Load an expedition by name.
--- @param name string
--- @return expedition.Expedition?
function M.load_by_name(name)
  local summaries = M.list()
  for _, s in ipairs(summaries) do
    if s.name == name then
      return M.load(s.id)
    end
  end
  vim.notify("[expedition] no expedition found with name: " .. name, vim.log.levels.ERROR)
  return nil
end

--- Get the currently active expedition (may be nil).
--- @return expedition.Expedition?
function M.get_active()
  return _active
end

--- Set the active expedition (in-memory only).
--- @param exp expedition.Expedition
function M.set_active(exp)
  _active = exp
  hooks.dispatch("expedition.activated", { expedition = exp })
end

--- Update an expedition's fields and persist.
--- @param id expedition.ExpeditionId
--- @param updates table
--- @return expedition.Expedition?
function M.update(id, updates)
  local pid = project_info()
  local dir = storage.ensure_expedition_dir(pid, id)
  local data, err = storage.read_json(dir .. "/expedition.json")
  if not data then
    vim.notify("[expedition] update failed: " .. tostring(err), vim.log.levels.ERROR)
    return nil
  end

  local util = require("expedition.util")
  for k, v in pairs(updates) do
    data[k] = v
  end
  data.updated_at = util.timestamp()

  storage.write_json(dir .. "/expedition.json", data)
  log.append(id, "expedition.updated", updates)
  hooks.dispatch("expedition.updated", { expedition = data, changes = updates })

  -- Update active if this is the active expedition
  if _active and _active.id == id then
    _active = data
  end

  return data
end

function M._reset()
  _active = nil
end

return M
