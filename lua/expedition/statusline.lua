--- Statusline component functions for expedition.nvim
--- Pure functions returning formatted strings. No dependency on any statusline plugin.
--- Users call these from lualine, heirline, raw statusline, etc.
local M = {}

local hooks = require("expedition.hooks")

-- ---------------------------------------------------------------------------
-- Cache
-- ---------------------------------------------------------------------------

--- @class expedition.StatuslineCache
--- @field expedition expedition.Expedition?
--- @field notes expedition.Note[]
--- @field waypoints expedition.Waypoint[]
--- @field conditions expedition.SummitCondition[]

--- @type expedition.StatuslineCache
local _cache = {
  expedition = nil,
  notes = {},
  waypoints = {},
  conditions = {},
}
local _dirty = true
local _registered = false

--- Refresh the cache from disk (one read per entity type).
local function refresh_cache()
  local expedition_mod = require("expedition.expedition")
  _cache.expedition = expedition_mod.get_active()
  if not _cache.expedition then
    _cache.notes = {}
    _cache.waypoints = {}
    _cache.conditions = {}
    _dirty = false
    return
  end

  local ok_n, note_mod = pcall(require, "expedition.note")
  _cache.notes = (ok_n and note_mod.list()) or {}

  local ok_r, route_mod = pcall(require, "expedition.route")
  _cache.waypoints = (ok_r and route_mod.get_route()) or {}

  local ok_s, summit_mod = pcall(require, "expedition.summit")
  _cache.conditions = (ok_s and summit_mod.list()) or {}

  _dirty = false
end

--- Ensure cache is fresh before reading.
local function ensure_cache()
  if _dirty then
    refresh_cache()
  end
end

--- Register hook listeners for cache invalidation (once).
function M.register()
  if _registered then return end
  _registered = true

  local events = {
    "expedition.activated", "expedition.updated",
    "note.created", "note.updated", "note.deleted", "note.drift_detected",
    "waypoint.created", "waypoint.updated", "waypoint.status_changed", "waypoint.deleted",
    "condition.created", "condition.updated", "condition.status_changed", "condition.deleted",
    "branch.switched",
  }
  for _, event in ipairs(events) do
    hooks.on(event, function() _dirty = true end)
  end
end

-- ---------------------------------------------------------------------------
-- Component functions
-- ---------------------------------------------------------------------------

--- Active expedition name + status.
--- @return string
function M.expedition()
  ensure_cache()
  local exp = _cache.expedition
  if not exp then return "" end
  return string.format("\u{26f0} %s [%s]", exp.name, exp.status)
end

--- Current route branch.
--- @return string
function M.branch()
  ensure_cache()
  if not _cache.expedition then return "" end
  local ok, route_mod = pcall(require, "expedition.route")
  if not ok then return "" end
  local b = route_mod.active_branch()
  if not b or b == "" then return "" end
  return "\u{238e} " .. b
end

--- Route completion summary.
--- @return string
function M.progress()
  ensure_cache()
  local wps = _cache.waypoints
  if #wps == 0 then return "" end
  local done = 0
  for _, wp in ipairs(wps) do
    if wp.status == "done" then done = done + 1 end
  end
  return string.format("Route: %d/%d", done, #wps)
end

--- Currently active waypoint title.
--- @return string
function M.active_waypoint()
  ensure_cache()
  for _, wp in ipairs(_cache.waypoints) do
    if wp.status == "active" then
      return "\u{2192} " .. wp.title
    end
  end
  return ""
end

--- Summit condition progress.
--- @return string
function M.conditions()
  ensure_cache()
  local conds = _cache.conditions
  if #conds == 0 then return "" end
  local met = 0
  for _, c in ipairs(conds) do
    if c.status == "met" then met = met + 1 end
  end
  return string.format("Summit: %d/%d", met, #conds)
end

--- Drifted note count for the current buffer.
--- @return string
function M.drift()
  ensure_cache()
  if not _cache.expedition then return "" end
  local count = 0
  for _, n in ipairs(_cache.notes) do
    if n.drift_status == "drifted" then
      count = count + 1
    end
  end
  if count == 0 then return "" end
  return string.format("~ %d drifted", count)
end

--- Whether an expedition is currently active.
--- @return boolean
function M.is_active()
  ensure_cache()
  return _cache.expedition ~= nil
end

--- Ready-made lualine component spec.
--- @return table
function M.lualine()
  return {
    function()
      local parts = {}
      local exp = M.expedition()
      if exp ~= "" then table.insert(parts, exp) end
      local prog = M.progress()
      if prog ~= "" then table.insert(parts, prog) end
      local wp = M.active_waypoint()
      if wp ~= "" then table.insert(parts, wp) end
      return table.concat(parts, "  ")
    end,
    cond = M.is_active,
    color = { fg = "#a0a0a0" },
  }
end

--- Force-invalidate cache (for testing or manual refresh).
function M.invalidate()
  _dirty = true
end

--- Reset module state (for testing).
function M._reset()
  _dirty = true
  _registered = false
  _cache = {
    expedition = nil,
    notes = {},
    waypoints = {},
    conditions = {},
  }
end

return M
