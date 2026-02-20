--- Side panel (vsplit buffer) for expedition.nvim
local hooks = require("expedition.hooks")

local M = {}

--- @type number?
local _buf = nil
--- @type number?
local _win = nil
--- @type table<number, { type: "note"|"waypoint"|"condition", id: expedition.NoteId|expedition.WaypointId|expedition.ConditionId }> line number → entry mapping
local _line_map = {}

--- Namespace for waypoint status highlights in the panel buffer.
local _ns = vim.api.nvim_create_namespace("expedition_panel_hl")

--- Status icons for waypoint display.
local STATUS_ICONS = {
  blocked   = "  ",
  ready     = "  ",
  active    = "  ",
  done      = "  ",
  abandoned = "  ",
}

--- Highlight group names per waypoint status.
local STATUS_HL = {
  blocked   = "ExpeditionWaypointBlocked",
  ready     = "ExpeditionWaypointReady",
  active    = "ExpeditionWaypointActive",
  done      = "ExpeditionWaypointDone",
  abandoned = "ExpeditionWaypointAbandoned",
}

--- Status icons for condition display.
local CONDITION_ICONS = {
  open      = "  [ ] ",
  met       = "  [x] ",
  abandoned = "  [~] ",
}

--- Highlight group names per condition status (reuse waypoint groups).
local CONDITION_HL = {
  open      = "ExpeditionWaypointReady",
  met       = "ExpeditionWaypointDone",
  abandoned = "ExpeditionWaypointAbandoned",
}

--- Check if the panel is open.
--- @return boolean
function M.is_open()
  return _win ~= nil and vim.api.nvim_win_is_valid(_win)
end

--- Close the panel.
function M.close()
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_close(_win, true)
  end
  _win = nil
  -- Don't delete buffer — it gets reused
end

--- Get the typed entry under the cursor, or nil.
--- @return { type: "note"|"waypoint"|"condition", id: expedition.NoteId|expedition.WaypointId|expedition.ConditionId }?
local function get_entry_under_cursor()
  if not _buf then return nil end
  local cursor = vim.api.nvim_win_get_cursor(0)
  return _line_map[cursor[1]]
end

--- Navigate to the anchor of the note on the current line.
local function navigate_to_note()
  if not _buf then return end
  local entry = get_entry_under_cursor()
  if not entry or entry.type ~= "note" then return end

  local note_mod = require("expedition.note")
  local note = note_mod.get(entry.id)
  if not note or not note.anchor then return end

  local anchor = note.anchor --[[@as expedition.Anchor]]
  local storage = require("expedition.storage")
  local root = storage.project_root()
  local abs_path = root .. "/" .. anchor.file

  -- Find or open the target window (not the panel window)
  local target_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if win ~= _win and vim.bo[buf].buftype == "" then
      target_win = win
      break
    end
  end

  if not target_win then
    -- Create a new split for the file
    vim.cmd("wincmd p")
    target_win = vim.api.nvim_get_current_win()
  else
    vim.api.nvim_set_current_win(target_win)
  end

  vim.cmd("edit " .. vim.fn.fnameescape(abs_path))
  local total = vim.api.nvim_buf_line_count(0)
  local target_line = math.min(anchor.line, total)
  vim.api.nvim_win_set_cursor(target_win, { target_line, 0 })
  vim.cmd("normal! zz")
end

--- Delete the note on the current line (with confirmation).
local function delete_note_under_cursor()
  if not _buf then return end
  local entry = get_entry_under_cursor()
  if not entry or entry.type ~= "note" then return end

  vim.ui.select({ "Yes", "No" }, { prompt = "Delete this note?" }, function(choice)
    if choice == "Yes" then
      local note_mod = require("expedition.note")
      note_mod.delete(entry.id)
      vim.notify("[expedition] note deleted", vim.log.levels.INFO)
    end
  end)
end

--- Add a note from the panel.
local function add_note_from_panel()
  local input = require("expedition.ui.input")
  -- Switch to previous window first so anchor captures the right buffer
  vim.cmd("wincmd p")
  input.open()
end

--- Expand waypoint details via vim.notify.
local function expand_waypoint()
  local entry = get_entry_under_cursor()
  if not entry or entry.type ~= "waypoint" then return end

  local route = require("expedition.route")
  local wp = route.get(entry.id)
  if not wp then return end

  local parts = {
    "Waypoint: " .. wp.title .. " [" .. wp.id .. "]",
    "Status: " .. wp.status,
  }
  if wp.description ~= "" then
    table.insert(parts, "Description: " .. wp.description)
  end
  if wp.reasoning ~= "" then
    table.insert(parts, "Reasoning: " .. wp.reasoning)
  end
  if #wp.depends_on > 0 then
    local dep_titles = {}
    for _, dep_id in ipairs(wp.depends_on) do
      local dep = route.get(dep_id)
      table.insert(dep_titles, dep and dep.title or dep_id)
    end
    table.insert(parts, "Depends on: " .. table.concat(dep_titles, ", "))
  end
  if #wp.linked_note_ids > 0 then
    table.insert(parts, "Linked notes: " .. #wp.linked_note_ids)
  end
  table.insert(parts, "Branch: " .. wp.branch)
  table.insert(parts, "Created: " .. wp.created_at)

  vim.notify(table.concat(parts, "\n"), vim.log.levels.INFO)
end

--- Toggle condition met/open on condition under cursor.
local function toggle_condition()
  local entry = get_entry_under_cursor()
  if not entry or entry.type ~= "condition" then return end

  local summit = require("expedition.summit")
  local c = summit.get(entry.id)
  if not c then return end

  if c.status == "met" then
    summit.set_status(entry.id, "open")
  else
    summit.set_status(entry.id, "met")
  end
end

--- Expand condition details via vim.notify.
local function expand_condition()
  local entry = get_entry_under_cursor()
  if not entry or entry.type ~= "condition" then return end

  local summit = require("expedition.summit")
  local c = summit.get(entry.id)
  if not c then return end

  local parts = {
    "Condition: " .. c.text .. " [" .. c.id .. "]",
    "Status: " .. c.status,
    "Created: " .. c.created_at,
  }
  vim.notify(table.concat(parts, "\n"), vim.log.levels.INFO)
end

--- Handle <CR> dispatcher: navigate for notes, expand for waypoints.
local function handle_cr()
  local entry = get_entry_under_cursor()
  if not entry then return end
  if entry.type == "note" then
    navigate_to_note()
  elseif entry.type == "waypoint" then
    expand_waypoint()
  elseif entry.type == "condition" then
    expand_condition()
  end
end

--- Toggle waypoint done/ready on waypoint under cursor.
local function toggle_waypoint_done()
  local entry = get_entry_under_cursor()
  if not entry or entry.type ~= "waypoint" then return end

  local route = require("expedition.route")
  local wp = route.get(entry.id)
  if not wp then return end

  if wp.status == "done" then
    route.set_status(entry.id, "ready")
  elseif wp.status == "ready" or wp.status == "active" then
    route.set_status(entry.id, "done")
  else
    vim.notify("[expedition] cannot toggle done from status: " .. wp.status, vim.log.levels.WARN)
  end
end

--- Set waypoint active under cursor.
local function set_waypoint_active()
  local entry = get_entry_under_cursor()
  if not entry or entry.type ~= "waypoint" then return end

  local route = require("expedition.route")
  route.set_status(entry.id, "active")
end

--- Mark waypoint abandoned under cursor (with confirmation).
local function mark_waypoint_abandoned()
  local entry = get_entry_under_cursor()
  if not entry or entry.type ~= "waypoint" then return end

  vim.ui.select({ "Yes", "No" }, { prompt = "Abandon this waypoint?" }, function(choice)
    if choice == "Yes" then
      local route = require("expedition.route")
      route.set_status(entry.id, "abandoned")
    end
  end)
end

--- Add a new waypoint from the panel.
local function add_waypoint_from_panel()
  vim.ui.input({ prompt = "Waypoint title: " }, function(title)
    if title and title ~= "" then
      local route = require("expedition.route")
      route.create_waypoint({ title = title })
    end
  end)
end

--- Add dependency from panel: cursor on waypoint, select from other waypoints.
local function add_dependency_from_panel()
  local entry = get_entry_under_cursor()
  if not entry or entry.type ~= "waypoint" then return end

  local route = require("expedition.route")
  local all = route.list()
  local choices = {}
  local choice_map = {}
  for _, wp in ipairs(all) do
    if wp.id ~= entry.id then
      local label = wp.title .. " [" .. wp.id .. "]"
      table.insert(choices, label)
      choice_map[label] = wp.id
    end
  end

  if #choices == 0 then
    vim.notify("[expedition] no other waypoints to depend on", vim.log.levels.INFO)
    return
  end

  vim.ui.select(choices, { prompt = "Add dependency:" }, function(choice)
    if choice then
      route.add_dependency(entry.id, choice_map[choice])
    end
  end)
end

--- Link note to waypoint: cursor on note line, select from waypoints.
local function link_note_to_waypoint()
  local entry = get_entry_under_cursor()
  if not entry or entry.type ~= "note" then
    vim.notify("[expedition] place cursor on a note line", vim.log.levels.WARN)
    return
  end

  local route = require("expedition.route")
  local all = route.list()
  if #all == 0 then
    vim.notify("[expedition] no waypoints to link to", vim.log.levels.INFO)
    return
  end

  local choices = {}
  local choice_map = {}
  for _, wp in ipairs(all) do
    local label = wp.title .. " [" .. wp.id .. "]"
    table.insert(choices, label)
    choice_map[label] = wp.id
  end

  vim.ui.select(choices, { prompt = "Link note to waypoint:" }, function(choice)
    if choice then
      route.link_note(entry.id, choice_map[choice])
    end
  end)
end

--- Apply extmark-based status highlighting to waypoint and condition lines.
local function apply_status_highlights(lines)
  if not _buf or not vim.api.nvim_buf_is_valid(_buf) then return end
  vim.api.nvim_buf_clear_namespace(_buf, _ns, 0, -1)
  for line_nr, entry in pairs(_line_map) do
    if line_nr <= #lines then
      if entry.type == "waypoint" then
        local route = require("expedition.route")
        local wp = route.get(entry.id)
        if wp then
          local hl = STATUS_HL[wp.status]
          if hl then
            vim.api.nvim_buf_add_highlight(_buf, _ns, hl, line_nr - 1, 0, -1)
          end
        end
      elseif entry.type == "condition" then
        local summit = require("expedition.summit")
        local c = summit.get(entry.id)
        if c then
          local hl = CONDITION_HL[c.status]
          if hl then
            vim.api.nvim_buf_add_highlight(_buf, _ns, hl, line_nr - 1, 0, -1)
          end
        end
      end
    end
  end
end

--- Render the panel content.
function M.refresh()
  if not _buf or not vim.api.nvim_buf_is_valid(_buf) then return end

  local expedition_mod = require("expedition.expedition")
  local note_mod = require("expedition.note")

  local active = expedition_mod.get_active()
  local lines = {}
  _line_map = {}

  if not active then
    lines = { "  No active expedition", "", "  Use :Expedition create <name>" }
  else
    -- Header
    table.insert(lines, "  " .. active.name)
    table.insert(lines, "  Status: " .. active.status)
    table.insert(lines, string.rep("─", 38))
    table.insert(lines, "")

    -- Summit conditions section
    local summit = require("expedition.summit")
    local conditions = summit.list()
    if #conditions > 0 then
      table.insert(lines, "  Summit Conditions")
      table.insert(lines, "")
      for _, c in ipairs(conditions) do
        local icon = CONDITION_ICONS[c.status] or "  [ ] "
        local text = c.text
        if #text > 28 then
          text = text:sub(1, 25) .. "..."
        end
        table.insert(lines, icon .. text)
        _line_map[#lines] = { type = "condition", id = c.id }
      end
      table.insert(lines, "")
    end

    -- Get all notes
    local notes = note_mod.list()

    -- Group notes by file
    local by_file = {}
    local unanchored = {}
    for _, note in ipairs(notes) do
      if note.anchor and note.anchor.file then
        local file = note.anchor.file
        if not by_file[file] then
          by_file[file] = {}
        end
        table.insert(by_file[file], note)
      else
        table.insert(unanchored, note)
      end
    end

    -- Render anchored notes grouped by file
    local files = {}
    for file in pairs(by_file) do
      table.insert(files, file)
    end
    table.sort(files)

    for _, file in ipairs(files) do
      table.insert(lines, "  " .. file)
      for _, note in ipairs(by_file[file]) do
        local line_info = ""
        if note.anchor then
          line_info = "L" .. note.anchor.line
          if note.anchor.symbol then
            line_info = line_info .. " " .. note.anchor.symbol
          end
        end
        if note.drift_status == "drifted" then
          line_info = line_info .. " ~"
        end
        table.insert(lines, "    " .. line_info)
        _line_map[#lines] = { type = "note", id = note.id }

        -- Render note body (first line, truncated)
        local body_line = note.body:match("^[^\n]*") or ""
        if #body_line > 34 then
          body_line = body_line:sub(1, 31) .. "..."
        end
        table.insert(lines, "    " .. body_line)
        _line_map[#lines] = { type = "note", id = note.id }

        -- Show tags if any
        if note.tags and #note.tags > 0 then
          table.insert(lines, "    " .. table.concat(
            vim.tbl_map(function(t) return "#" .. t end, note.tags), " "
          ))
          _line_map[#lines] = { type = "note", id = note.id }
        end
        table.insert(lines, "")
      end
    end

    -- Render unanchored notes
    if #unanchored > 0 then
      table.insert(lines, "  General Notes")
      for _, note in ipairs(unanchored) do
        local body_line = note.body:match("^[^\n]*") or ""
        if #body_line > 34 then
          body_line = body_line:sub(1, 31) .. "..."
        end
        table.insert(lines, "    " .. body_line)
        _line_map[#lines] = { type = "note", id = note.id }
        if note.tags and #note.tags > 0 then
          table.insert(lines, "    " .. table.concat(
            vim.tbl_map(function(t) return "#" .. t end, note.tags), " "
          ))
          _line_map[#lines] = { type = "note", id = note.id }
        end
        table.insert(lines, "")
      end
    end

    if #notes == 0 then
      table.insert(lines, "  No notes yet")
      table.insert(lines, "  Press 'a' to add one")
      table.insert(lines, "")
    end

    -- Route section
    local route = require("expedition.route")
    table.insert(lines, string.rep("─", 38))
    table.insert(lines, "  Route [" .. route.active_branch() .. "]")
    table.insert(lines, "")

    local waypoints = route.get_route(route.active_branch())
    if #waypoints == 0 then
      table.insert(lines, "  No waypoints yet")
      table.insert(lines, "  Press 'o' to add one")
    else
      for _, wp in ipairs(waypoints) do
        local icon = STATUS_ICONS[wp.status] or "  "
        local title = wp.title
        if #title > 30 then
          title = title:sub(1, 27) .. "..."
        end
        table.insert(lines, icon .. title)
        _line_map[#lines] = { type = "waypoint", id = wp.id }

        -- Show blocked deps info
        if wp.status == "blocked" then
          local blocked_names = {}
          for _, dep_id in ipairs(wp.depends_on) do
            local dep = route.get(dep_id)
            if dep and dep.status ~= "done" then
              table.insert(blocked_names, dep.title)
            end
          end
          if #blocked_names > 0 then
            local info = "    waiting: " .. table.concat(blocked_names, ", ")
            if #info > 38 then
              info = info:sub(1, 35) .. "..."
            end
            table.insert(lines, info)
            _line_map[#lines] = { type = "waypoint", id = wp.id }
          end
        end

        -- Show linked note count
        if #wp.linked_note_ids > 0 then
          table.insert(lines, "    " .. #wp.linked_note_ids .. " linked note(s)")
          _line_map[#lines] = { type = "waypoint", id = wp.id }
        end
      end
    end
  end

  vim.bo[_buf].modifiable = true
  vim.api.nvim_buf_set_lines(_buf, 0, -1, false, lines)
  vim.bo[_buf].modifiable = false

  -- Apply status highlights for waypoints and conditions
  apply_status_highlights(lines)
end

--- Open the panel.
--- @return number? buf
--- @return number? win
function M.open()
  if M.is_open() then
    M.refresh()
    return _buf, _win
  end

  local config = require("expedition.config")
  local position = config.val("panel.position")
  local width = config.val("panel.width")

  -- Create buffer if needed
  if not _buf or not vim.api.nvim_buf_is_valid(_buf) then
    _buf = vim.api.nvim_create_buf(false, true)
    vim.bo[_buf].buftype = "nofile"
    vim.bo[_buf].filetype = "expedition"
    vim.bo[_buf].bufhidden = "hide"
    vim.bo[_buf].swapfile = false

    -- Buffer-local keymaps
    vim.keymap.set("n", "<CR>", handle_cr, { buffer = _buf, desc = "Activate entry" })
    vim.keymap.set("n", "q", M.close, { buffer = _buf, desc = "Close panel" })
    vim.keymap.set("n", "r", M.refresh, { buffer = _buf, desc = "Refresh panel" })
    vim.keymap.set("n", "a", add_note_from_panel, { buffer = _buf, desc = "Add note" })
    vim.keymap.set("n", "d", delete_note_under_cursor, { buffer = _buf, desc = "Delete note" })
    -- Waypoint keymaps
    vim.keymap.set("n", "x", toggle_waypoint_done, { buffer = _buf, desc = "Toggle waypoint done/ready" })
    vim.keymap.set("n", "A", set_waypoint_active, { buffer = _buf, desc = "Set waypoint active" })
    vim.keymap.set("n", "X", mark_waypoint_abandoned, { buffer = _buf, desc = "Mark waypoint abandoned" })
    vim.keymap.set("n", "o", add_waypoint_from_panel, { buffer = _buf, desc = "Add waypoint" })
    vim.keymap.set("n", "D", add_dependency_from_panel, { buffer = _buf, desc = "Add dependency" })
    vim.keymap.set("n", "l", link_note_to_waypoint, { buffer = _buf, desc = "Link note to waypoint" })
    -- Condition keymaps
    vim.keymap.set("n", "c", toggle_condition, { buffer = _buf, desc = "Toggle condition met/open" })
    vim.keymap.set("n", "K", function()
      local entry = get_entry_under_cursor()
      if entry and entry.type == "note" then
        require("expedition.drift").acknowledge(entry.id)
      end
    end, { buffer = _buf, desc = "Acknowledge drift" })
    vim.keymap.set("n", "B", function()
      local route_mod = require("expedition.route")
      local branches = route_mod.list_branches()
      vim.ui.select(branches, { prompt = "Switch branch:" }, function(choice)
        if choice then
          route_mod.switch_branch(choice)
        end
      end)
    end, { buffer = _buf, desc = "Switch branch" })
  end

  -- Open the split
  local cmd = position == "left" and "topleft vsplit" or "botright vsplit"
  vim.cmd(cmd)
  _win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(_win, _buf)
  vim.api.nvim_win_set_width(_win, width)

  -- Window options
  vim.wo[_win].winfixwidth = true
  vim.wo[_win].number = false
  vim.wo[_win].relativenumber = false
  vim.wo[_win].signcolumn = "no"
  vim.wo[_win].cursorline = true
  vim.wo[_win].wrap = true
  vim.wo[_win].spell = false

  M.refresh()

  return _buf, _win
end

--- Toggle the panel open/closed.
function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

-- Subscribe to hooks for auto-refresh
local function schedule_refresh()
  if M.is_open() then
    vim.schedule(M.refresh)
  end
end

hooks.on("note.created", schedule_refresh)
hooks.on("note.updated", schedule_refresh)
hooks.on("note.deleted", schedule_refresh)
hooks.on("expedition.activated", schedule_refresh)
hooks.on("waypoint.created", schedule_refresh)
hooks.on("waypoint.updated", schedule_refresh)
hooks.on("waypoint.status_changed", schedule_refresh)
hooks.on("waypoint.deleted", schedule_refresh)
hooks.on("waypoint.note_linked", schedule_refresh)
hooks.on("note.drift_detected", schedule_refresh)
hooks.on("condition.created", schedule_refresh)
hooks.on("condition.updated", schedule_refresh)
hooks.on("condition.status_changed", schedule_refresh)
hooks.on("condition.deleted", schedule_refresh)
hooks.on("branch.created", schedule_refresh)
hooks.on("branch.switched", schedule_refresh)
hooks.on("branch.merged", schedule_refresh)

return M
