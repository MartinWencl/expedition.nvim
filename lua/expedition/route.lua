--- Waypoint DAG (route) management for expedition.nvim
--- Provides waypoint CRUD, topological sort, status computation, dependency
--- management, and note linking.
local types = require("expedition.types")
local storage = require("expedition.storage")
local hooks = require("expedition.hooks")
local log = require("expedition.log")
local expedition_mod = require("expedition.expedition")

local M = {}

--- Explicit statuses that are stored as-is (not recomputed).
local EXPLICIT_STATUSES = { active = true, done = true, abandoned = true }

--- Valid status transitions.
--- @type table<string, table<string, boolean>>
local VALID_TRANSITIONS = {
  blocked   = { active = true, abandoned = true },
  ready     = { active = true, done = true, abandoned = true },
  active    = { done = true, abandoned = true, ready = true },
  done      = { active = true, ready = true },
  abandoned = { ready = true },
}

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

--- Get the path to route.json for the active expedition.
--- @return string?
local function route_path()
  local active = expedition_mod.get_active()
  if not active then return nil end
  return expedition_mod.expedition_dir(active.id) .. "/route.json"
end

--- Read waypoints from route.json, handling the legacy empty-object stub.
--- @return expedition.Waypoint[]
local function read_route()
  local path = route_path()
  if not path then return {} end
  local data = storage.read_json(path)
  if not data then return {} end
  -- Legacy Phase 1 stub writes {} (empty object).  Detect and return empty list.
  if not data[1] and next(data) == nil then
    return {}
  end
  -- Already an array
  return data
end

--- Persist waypoints array to route.json.
--- @param waypoints expedition.Waypoint[]
--- @return boolean
local function write_route(waypoints)
  local path = route_path()
  if not path then return false end
  return storage.write_json(path, waypoints)
end

-- ---------------------------------------------------------------------------
-- Status computation
-- ---------------------------------------------------------------------------

--- Build a lookup table from waypoint ID → waypoint.
--- @param waypoints expedition.Waypoint[]
--- @return table<expedition.WaypointId, expedition.Waypoint>
local function index_by_id(waypoints)
  local idx = {}
  for _, wp in ipairs(waypoints) do
    idx[wp.id] = wp
  end
  return idx
end

--- Compute derived statuses (blocked/ready) for all waypoints in-place.
--- Explicit statuses (active/done/abandoned) are left unchanged.
--- @param waypoints expedition.Waypoint[]
local function compute_statuses(waypoints)
  local idx = index_by_id(waypoints)
  for _, wp in ipairs(waypoints) do
    if not EXPLICIT_STATUSES[wp.status] then
      -- Check if all dependencies are done
      local all_done = true
      for _, dep_id in ipairs(wp.depends_on) do
        local dep = idx[dep_id]
        if not dep or dep.status ~= "done" then
          all_done = false
          break
        end
      end
      if #wp.depends_on == 0 or all_done then
        wp.status = "ready"
      else
        wp.status = "blocked"
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Graph operations
-- ---------------------------------------------------------------------------

--- Topological sort using Kahn's algorithm.
--- Falls back to appending remaining nodes in creation order for cycles.
--- @param waypoints expedition.Waypoint[]
--- @return expedition.Waypoint[]
function M.topo_sort(waypoints)
  if #waypoints == 0 then return {} end

  local idx = index_by_id(waypoints)
  -- Build in-degree counts (only count deps that exist)
  local in_degree = {}
  local adj = {} -- dep_id → list of waypoint ids that depend on it
  for _, wp in ipairs(waypoints) do
    in_degree[wp.id] = 0
    adj[wp.id] = adj[wp.id] or {}
  end
  for _, wp in ipairs(waypoints) do
    for _, dep_id in ipairs(wp.depends_on) do
      if idx[dep_id] then
        in_degree[wp.id] = (in_degree[wp.id] or 0) + 1
        adj[dep_id] = adj[dep_id] or {}
        table.insert(adj[dep_id], wp.id)
      end
    end
  end

  -- Collect nodes with no incoming edges
  local queue = {}
  for _, wp in ipairs(waypoints) do
    if in_degree[wp.id] == 0 then
      table.insert(queue, wp.id)
    end
  end

  local sorted = {}
  local visited = {}
  while #queue > 0 do
    local id = table.remove(queue, 1)
    visited[id] = true
    table.insert(sorted, idx[id])
    for _, next_id in ipairs(adj[id] or {}) do
      in_degree[next_id] = in_degree[next_id] - 1
      if in_degree[next_id] == 0 then
        table.insert(queue, next_id)
      end
    end
  end

  -- Fallback: append remaining nodes (cycle or corrupted data) in creation order
  for _, wp in ipairs(waypoints) do
    if not visited[wp.id] then
      table.insert(sorted, wp)
    end
  end

  return sorted
end

--- Check if adding dep_id as a dependency of wp_id would create a cycle.
--- Returns true if it WOULD create a cycle.
--- @param waypoints expedition.Waypoint[]
--- @param wp_id expedition.WaypointId
--- @param dep_id expedition.WaypointId
--- @return boolean
function M.would_cycle(waypoints, wp_id, dep_id)
  -- Adding dep_id as a dependency of wp_id creates the edge wp_id → dep_id.
  -- A cycle exists if wp_id is reachable from dep_id by following depends_on edges.
  local idx = index_by_id(waypoints)

  local visited = {}
  local stack = { dep_id }
  while #stack > 0 do
    local current = table.remove(stack)
    if current == wp_id then
      return true
    end
    if not visited[current] then
      visited[current] = true
      local wp = idx[current]
      if wp then
        for _, next_dep in ipairs(wp.depends_on) do
          if not visited[next_dep] then
            table.insert(stack, next_dep)
          end
        end
      end
    end
  end

  return false
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Create a new waypoint.
--- @param opts table { title: string, description?, depends_on?, reasoning?, branch? }
--- @return expedition.Waypoint?
function M.create_waypoint(opts)
  local active = expedition_mod.get_active()
  if not active then
    vim.notify("[expedition] no active expedition", vim.log.levels.ERROR)
    return nil
  end

  opts = opts or {}
  if not opts.title or opts.title == "" then
    vim.notify("[expedition] waypoint title is required", vim.log.levels.ERROR)
    return nil
  end

  local waypoints = read_route()
  local idx = index_by_id(waypoints)

  -- Validate dependencies exist
  local depends_on = opts.depends_on or {}
  for _, dep_id in ipairs(depends_on) do
    if not idx[dep_id] then
      vim.notify("[expedition] dependency not found: " .. dep_id, vim.log.levels.ERROR)
      return nil
    end
  end

  local config = require("expedition.config")
  local wp = types.new_waypoint(opts.title, {
    description = opts.description,
    depends_on = depends_on,
    reasoning = opts.reasoning,
    branch = opts.branch or config.val("route.default_branch"),
  })

  table.insert(waypoints, wp)
  compute_statuses(waypoints)
  write_route(waypoints)

  log.append(active.id, "waypoint.created", { waypoint_id = wp.id, title = wp.title })
  hooks.dispatch("waypoint.created", { waypoint = wp })

  return wp
end

--- Update a waypoint's non-status fields.
--- @param id expedition.WaypointId
--- @param changes table
--- @return expedition.Waypoint?
function M.update_waypoint(id, changes)
  local active = expedition_mod.get_active()
  if not active then return nil end

  local util = require("expedition.util")
  local waypoints = read_route()
  for i, wp in ipairs(waypoints) do
    if wp.id == id then
      -- Apply changes (excluding status — use set_status for that)
      for k, v in pairs(changes) do
        if k ~= "status" and k ~= "id" and k ~= "created_at" then
          wp[k] = v
        end
      end
      wp.updated_at = util.timestamp()
      waypoints[i] = wp

      -- Recompute if deps changed
      compute_statuses(waypoints)
      write_route(waypoints)

      log.append(active.id, "waypoint.updated", { waypoint_id = id, changes = changes })
      hooks.dispatch("waypoint.updated", { waypoint = wp, changes = changes })
      return wp
    end
  end

  vim.notify("[expedition] waypoint not found: " .. id, vim.log.levels.ERROR)
  return nil
end

--- Set a waypoint's explicit status with transition validation.
--- @param id expedition.WaypointId
--- @param status string
--- @return expedition.Waypoint?
function M.set_status(id, status)
  local active = expedition_mod.get_active()
  if not active then return nil end

  local util = require("expedition.util")
  local waypoints = read_route()
  for i, wp in ipairs(waypoints) do
    if wp.id == id then
      -- Validate transition
      local allowed = VALID_TRANSITIONS[wp.status]
      if not allowed or not allowed[status] then
        vim.notify(
          string.format("[expedition] invalid transition: %s → %s", wp.status, status),
          vim.log.levels.ERROR
        )
        return nil
      end

      local old_status = wp.status
      wp.status = status
      wp.updated_at = util.timestamp()
      waypoints[i] = wp

      -- Recompute cascade (changing one waypoint may affect dependents)
      compute_statuses(waypoints)
      write_route(waypoints)

      log.append(active.id, "waypoint.status_changed", {
        waypoint_id = id,
        from = old_status,
        to = status,
      })
      hooks.dispatch("waypoint.status_changed", {
        waypoint = wp,
        from = old_status,
        to = status,
      })
      return wp
    end
  end

  vim.notify("[expedition] waypoint not found: " .. id, vim.log.levels.ERROR)
  return nil
end

--- Get all waypoints topo-sorted with computed statuses, optional branch filter.
--- @param branch string?
--- @return expedition.Waypoint[]
function M.get_route(branch)
  local waypoints = read_route()
  compute_statuses(waypoints)
  local sorted = M.topo_sort(waypoints)
  if branch then
    local filtered = {}
    for _, wp in ipairs(sorted) do
      if wp.branch == branch then
        table.insert(filtered, wp)
      end
    end
    return filtered
  end
  return sorted
end

--- Get waypoints where status == "ready".
--- @return expedition.Waypoint[]
function M.get_ready()
  local waypoints = read_route()
  compute_statuses(waypoints)
  local result = {}
  for _, wp in ipairs(waypoints) do
    if wp.status == "ready" then
      table.insert(result, wp)
    end
  end
  return result
end

--- Get a single waypoint by ID (with computed status).
--- @param id expedition.WaypointId
--- @return expedition.Waypoint?
function M.get(id)
  local waypoints = read_route()
  compute_statuses(waypoints)
  for _, wp in ipairs(waypoints) do
    if wp.id == id then
      return wp
    end
  end
  return nil
end

--- Delete a waypoint, cleaning up all references.
--- @param id expedition.WaypointId
--- @return boolean
function M.delete_waypoint(id)
  local active = expedition_mod.get_active()
  if not active then return false end

  local waypoints = read_route()
  local found = false
  local removed_wp = nil

  -- Find and remove the waypoint
  for i, wp in ipairs(waypoints) do
    if wp.id == id then
      removed_wp = wp
      table.remove(waypoints, i)
      found = true
      break
    end
  end

  if not found then
    vim.notify("[expedition] waypoint not found: " .. id, vim.log.levels.ERROR)
    return false
  end

  -- Remove from all depends_on lists
  for _, wp in ipairs(waypoints) do
    local new_deps = {}
    for _, dep_id in ipairs(wp.depends_on) do
      if dep_id ~= id then
        table.insert(new_deps, dep_id)
      end
    end
    wp.depends_on = new_deps
  end

  -- Clean up note links
  if removed_wp and removed_wp.linked_note_ids then
    local note_mod = require("expedition.note")
    for _, note_id in ipairs(removed_wp.linked_note_ids) do
      local note = note_mod.get(note_id)
      if note and note.meta and note.meta.waypoint_id == id then
        local meta = vim.tbl_extend("force", note.meta, {})
        meta.waypoint_id = nil
        note_mod.update(note_id, { meta = meta })
      end
    end
  end

  compute_statuses(waypoints)
  write_route(waypoints)

  log.append(active.id, "waypoint.deleted", { waypoint_id = id })
  hooks.dispatch("waypoint.deleted", { waypoint_id = id })

  return true
end

--- Add a dependency (with cycle check).
--- @param wp_id expedition.WaypointId
--- @param dep_id expedition.WaypointId
--- @return boolean
function M.add_dependency(wp_id, dep_id)
  local active = expedition_mod.get_active()
  if not active then return false end

  if wp_id == dep_id then
    vim.notify("[expedition] cannot depend on self", vim.log.levels.ERROR)
    return false
  end

  local waypoints = read_route()
  local idx = index_by_id(waypoints)

  if not idx[wp_id] then
    vim.notify("[expedition] waypoint not found: " .. wp_id, vim.log.levels.ERROR)
    return false
  end
  if not idx[dep_id] then
    vim.notify("[expedition] dependency not found: " .. dep_id, vim.log.levels.ERROR)
    return false
  end

  -- Check for existing dependency
  for _, d in ipairs(idx[wp_id].depends_on) do
    if d == dep_id then
      vim.notify("[expedition] dependency already exists", vim.log.levels.WARN)
      return false
    end
  end

  -- Cycle check
  if M.would_cycle(waypoints, wp_id, dep_id) then
    vim.notify("[expedition] cannot add dependency: would create cycle", vim.log.levels.ERROR)
    return false
  end

  local util = require("expedition.util")
  for i, wp in ipairs(waypoints) do
    if wp.id == wp_id then
      table.insert(wp.depends_on, dep_id)
      wp.updated_at = util.timestamp()
      waypoints[i] = wp
      break
    end
  end

  compute_statuses(waypoints)
  write_route(waypoints)

  log.append(active.id, "waypoint.updated", { waypoint_id = wp_id, added_dep = dep_id })
  hooks.dispatch("waypoint.updated", { waypoint = idx[wp_id] })

  return true
end

--- Remove a dependency.
--- @param wp_id expedition.WaypointId
--- @param dep_id expedition.WaypointId
--- @return boolean
function M.remove_dependency(wp_id, dep_id)
  local active = expedition_mod.get_active()
  if not active then return false end

  local util = require("expedition.util")
  local waypoints = read_route()
  for i, wp in ipairs(waypoints) do
    if wp.id == wp_id then
      local new_deps = {}
      local removed = false
      for _, d in ipairs(wp.depends_on) do
        if d == dep_id then
          removed = true
        else
          table.insert(new_deps, d)
        end
      end
      if not removed then
        vim.notify("[expedition] dependency not found", vim.log.levels.WARN)
        return false
      end
      wp.depends_on = new_deps
      wp.updated_at = util.timestamp()
      waypoints[i] = wp

      compute_statuses(waypoints)
      write_route(waypoints)

      log.append(active.id, "waypoint.updated", { waypoint_id = wp_id, removed_dep = dep_id })
      hooks.dispatch("waypoint.updated", { waypoint = wp })
      return true
    end
  end

  vim.notify("[expedition] waypoint not found: " .. wp_id, vim.log.levels.ERROR)
  return false
end

--- Link a note to a waypoint (bidirectional).
--- @param note_id expedition.NoteId
--- @param wp_id expedition.WaypointId
--- @return boolean
function M.link_note(note_id, wp_id)
  local active = expedition_mod.get_active()
  if not active then return false end

  local note_mod = require("expedition.note")
  local note = note_mod.get(note_id)
  if not note then
    vim.notify("[expedition] note not found: " .. note_id, vim.log.levels.ERROR)
    return false
  end

  local util = require("expedition.util")
  local waypoints = read_route()
  for i, wp in ipairs(waypoints) do
    if wp.id == wp_id then
      -- Check if already linked
      for _, nid in ipairs(wp.linked_note_ids) do
        if nid == note_id then
          vim.notify("[expedition] note already linked", vim.log.levels.WARN)
          return false
        end
      end

      table.insert(wp.linked_note_ids, note_id)
      wp.updated_at = util.timestamp()
      waypoints[i] = wp
      write_route(waypoints)

      -- Update note side
      local meta = vim.tbl_extend("force", note.meta or {}, { waypoint_id = wp_id })
      note_mod.update(note_id, { meta = meta })

      log.append(active.id, "waypoint.note_linked", { waypoint_id = wp_id, note_id = note_id })
      hooks.dispatch("waypoint.note_linked", { waypoint_id = wp_id, note_id = note_id })
      return true
    end
  end

  vim.notify("[expedition] waypoint not found: " .. wp_id, vim.log.levels.ERROR)
  return false
end

--- Unlink a note from a waypoint (bidirectional).
--- @param note_id expedition.NoteId
--- @param wp_id expedition.WaypointId
--- @return boolean
function M.unlink_note(note_id, wp_id)
  local active = expedition_mod.get_active()
  if not active then return false end

  local note_mod = require("expedition.note")
  local util = require("expedition.util")
  local waypoints = read_route()

  for i, wp in ipairs(waypoints) do
    if wp.id == wp_id then
      local new_ids = {}
      local found = false
      for _, nid in ipairs(wp.linked_note_ids) do
        if nid == note_id then
          found = true
        else
          table.insert(new_ids, nid)
        end
      end
      if not found then
        vim.notify("[expedition] note not linked to this waypoint", vim.log.levels.WARN)
        return false
      end

      wp.linked_note_ids = new_ids
      wp.updated_at = util.timestamp()
      waypoints[i] = wp
      write_route(waypoints)

      -- Update note side
      local note = note_mod.get(note_id)
      if note then
        local meta = vim.tbl_extend("force", note.meta or {}, {})
        meta.waypoint_id = nil
        note_mod.update(note_id, { meta = meta })
      end

      return true
    end
  end

  vim.notify("[expedition] waypoint not found: " .. wp_id, vim.log.levels.ERROR)
  return false
end

--- List all waypoints with computed statuses (unsorted).
--- @return expedition.Waypoint[]
function M.list()
  local waypoints = read_route()
  compute_statuses(waypoints)
  return waypoints
end

-- ---------------------------------------------------------------------------
-- Branch API
-- ---------------------------------------------------------------------------

--- @type string? session-scoped active branch
local _active_branch = nil

--- Get the path to branches.json for the active expedition.
--- @return string?
local function branches_path()
  local active = expedition_mod.get_active()
  if not active then return nil end
  return expedition_mod.expedition_dir(active.id) .. "/branches.json"
end

--- Read branches from branches.json.
--- @return expedition.Branch[]
local function read_branches()
  local path = branches_path()
  if not path then return {} end
  local data = storage.read_json(path)
  if not data then return {} end
  if not data[1] and next(data) == nil then return {} end
  return data
end

--- Persist branches array to branches.json.
--- @param branches expedition.Branch[]
--- @return boolean
local function write_branches(branches)
  local path = branches_path()
  if not path then return false end
  return storage.write_json(path, branches)
end

--- Get the active branch name.
--- @return string
function M.active_branch()
  local config = require("expedition.config")
  return _active_branch or config.val("route.default_branch")
end

--- Create a new named branch.
--- @param name string
--- @param reasoning string?
--- @return expedition.Branch?
function M.create_branch(name, reasoning)
  local active = expedition_mod.get_active()
  if not active then
    vim.notify("[expedition] no active expedition", vim.log.levels.ERROR)
    return nil
  end

  if not name or name == "" then
    vim.notify("[expedition] branch name is required", vim.log.levels.ERROR)
    return nil
  end

  local branches = read_branches()
  for _, b in ipairs(branches) do
    if b.name == name then
      vim.notify("[expedition] branch already exists: " .. name, vim.log.levels.ERROR)
      return nil
    end
  end

  local branch = types.new_branch(name, reasoning)
  table.insert(branches, branch)
  write_branches(branches)

  log.append(active.id, "branch.created", { branch = name })
  hooks.dispatch("branch.created", { branch = branch })

  vim.notify("[expedition] branch created: " .. name, vim.log.levels.INFO)
  return branch
end

--- Switch to a named branch.
--- @param name string
function M.switch_branch(name)
  local active = expedition_mod.get_active()
  if not active then
    vim.notify("[expedition] no active expedition", vim.log.levels.ERROR)
    return
  end

  -- Validate: branch exists in metadata, waypoints, or is default
  local config = require("expedition.config")
  local default = config.val("route.default_branch")
  local valid = (name == default)

  if not valid then
    local branches = read_branches()
    for _, b in ipairs(branches) do
      if b.name == name then
        valid = true
        break
      end
    end
  end

  if not valid then
    local waypoints = read_route()
    for _, wp in ipairs(waypoints) do
      if wp.branch == name then
        valid = true
        break
      end
    end
  end

  if not valid then
    vim.notify("[expedition] branch not found: " .. name, vim.log.levels.ERROR)
    return
  end

  local old = M.active_branch()
  _active_branch = name

  log.append(active.id, "branch.switched", { from = old, to = name })
  hooks.dispatch("branch.switched", { from = old, to = name })

  vim.notify("[expedition] switched to branch: " .. name, vim.log.levels.INFO)
end

--- List all known branches (metadata + implicit from waypoints + default).
--- @return string[]
function M.list_branches()
  local config = require("expedition.config")
  local default = config.val("route.default_branch")
  local seen = { [default] = true }
  local result = { default }

  local branches = read_branches()
  for _, b in ipairs(branches) do
    if not seen[b.name] then
      seen[b.name] = true
      table.insert(result, b.name)
    end
  end

  local waypoints = read_route()
  for _, wp in ipairs(waypoints) do
    if wp.branch and not seen[wp.branch] then
      seen[wp.branch] = true
      table.insert(result, wp.branch)
    end
  end

  return result
end

--- Merge waypoints from source branch into target branch (copies with reset status).
--- @param source string
--- @param target string
function M.merge_branch(source, target)
  local active = expedition_mod.get_active()
  if not active then
    vim.notify("[expedition] no active expedition", vim.log.levels.ERROR)
    return
  end

  local util = require("expedition.util")
  local waypoints = read_route()

  -- Collect source waypoints
  local source_wps = {}
  for _, wp in ipairs(waypoints) do
    if wp.branch == source then
      table.insert(source_wps, wp)
    end
  end

  if #source_wps == 0 then
    vim.notify("[expedition] no waypoints on branch: " .. source, vim.log.levels.WARN)
    return
  end

  -- Build old_id → new_id map
  local id_map = {}
  for _, wp in ipairs(source_wps) do
    id_map[wp.id] = util.id()
  end

  -- Create copies on target branch with remapped deps
  local count = 0
  for _, wp in ipairs(source_wps) do
    local new_deps = {}
    for _, dep_id in ipairs(wp.depends_on) do
      if id_map[dep_id] then
        table.insert(new_deps, id_map[dep_id])
      else
        table.insert(new_deps, dep_id)
      end
    end

    local now = util.timestamp()
    local new_wp = {
      id = id_map[wp.id],
      title = wp.title,
      description = wp.description,
      status = "ready",
      depends_on = new_deps,
      reasoning = wp.reasoning,
      linked_note_ids = {},
      branch = target,
      created_at = now,
      updated_at = now,
    }
    table.insert(waypoints, new_wp)
    count = count + 1
  end

  compute_statuses(waypoints)
  write_route(waypoints)

  log.append(active.id, "branch.merged", { source = source, target = target, count = count })
  hooks.dispatch("branch.merged", { source = source, target = target, count = count })

  vim.notify(
    string.format("[expedition] merged %d waypoint(s) from %s to %s", count, source, target),
    vim.log.levels.INFO
  )
end

function M._reset()
  _active_branch = nil
end

return M
