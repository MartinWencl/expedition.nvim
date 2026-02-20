--- Telescope pickers for expedition.nvim
--- Soft-depends on telescope — errors only when a picker is actually called.
local M = {}

--- Status icons for waypoint display (matching panel.lua).
local WP_STATUS_ICONS = {
  blocked   = "\u{2b55}",
  ready     = "\u{25cb}",
  active    = "\u{25cf}",
  done      = "\u{2714}",
  abandoned = "\u{2716}",
}

--- Status icons for condition display.
local COND_STATUS_ICONS = {
  open      = "[ ]",
  met       = "[x]",
  abandoned = "[~]",
}

--- Require telescope modules, error if not installed.
--- @return table pickers
--- @return table finders
--- @return table conf
--- @return table actions
--- @return table action_state
--- @return table previewers
local function telescope_require()
  local has_telescope, _ = pcall(require, "telescope")
  if not has_telescope then
    error("[expedition] telescope.nvim is required for picker functionality")
  end
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")
  return pickers, finders, conf, actions, action_state, previewers
end

--- Jump to a file:line location.
--- @param file string project-relative path
--- @param line number
local function jump_to(file, line)
  local storage = require("expedition.storage")
  local root = storage.project_root()
  local abs_path = root .. "/" .. file
  vim.cmd("edit " .. vim.fn.fnameescape(abs_path))
  if line and line > 0 then
    local ok = pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
    if ok then
      vim.cmd("normal! zz")
    end
  end
end

--- Search notes by body text.
--- @param opts table? { tag?: string, file?: string, drifted?: boolean }
function M.notes(opts)
  opts = opts or {}
  local pickers, finders, conf, actions, action_state, _ = telescope_require()

  local note_mod = require("expedition.note")
  local notes = note_mod.list()

  -- Apply filters
  if opts.tag then
    local filtered = {}
    for _, n in ipairs(notes) do
      for _, t in ipairs(n.tags or {}) do
        if t == opts.tag then
          table.insert(filtered, n)
          break
        end
      end
    end
    notes = filtered
  end
  if opts.file then
    local filtered = {}
    for _, n in ipairs(notes) do
      if n.anchor and n.anchor.file == opts.file then
        table.insert(filtered, n)
      end
    end
    notes = filtered
  end
  if opts.drifted then
    local filtered = {}
    for _, n in ipairs(notes) do
      if n.drift_status == "drifted" then
        table.insert(filtered, n)
      end
    end
    notes = filtered
  end

  -- Sort by created_at descending
  table.sort(notes, function(a, b)
    return (a.created_at or "") > (b.created_at or "")
  end)

  local storage = require("expedition.storage")
  local root = storage.project_root()

  pickers.new(opts, {
    prompt_title = "Expedition Notes",
    finder = finders.new_table({
      results = notes,
      entry_maker = function(note)
        local tags_str = ""
        if note.tags and #note.tags > 0 then
          tags_str = "[" .. table.concat(note.tags, ",") .. "] "
        end
        local body_first = (note.body:match("^[^\n]*") or ""):sub(1, 60)
        local loc = ""
        local filename = nil
        local lnum = nil
        if note.anchor then
          loc = " \u{2014} " .. note.anchor.file .. ":" .. note.anchor.line
          filename = root .. "/" .. note.anchor.file
          lnum = note.anchor.line
        end
        local display = tags_str .. body_first .. loc

        return {
          value = note,
          display = display,
          ordinal = (note.body or "") .. " " .. table.concat(note.tags or {}, " "),
          filename = filename,
          lnum = lnum,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = conf.file_previewer(opts),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry and entry.value.anchor then
          jump_to(entry.value.anchor.file, entry.value.anchor.line)
        end
      end)
      return true
    end,
  }):find()
end

--- Search waypoints.
--- @param opts table? { status?: string, branch?: string }
function M.waypoints(opts)
  opts = opts or {}
  local pickers, finders, conf, _, _, previewers = telescope_require()

  local route_mod = require("expedition.route")
  local waypoints = route_mod.get_route()

  -- Apply filters
  if opts.status then
    local filtered = {}
    for _, wp in ipairs(waypoints) do
      if wp.status == opts.status then
        table.insert(filtered, wp)
      end
    end
    waypoints = filtered
  end
  if opts.branch then
    local filtered = {}
    for _, wp in ipairs(waypoints) do
      if wp.branch == opts.branch then
        table.insert(filtered, wp)
      end
    end
    waypoints = filtered
  end

  pickers.new(opts, {
    prompt_title = "Expedition Waypoints",
    finder = finders.new_table({
      results = waypoints,
      entry_maker = function(wp)
        local icon = WP_STATUS_ICONS[wp.status] or "?"
        local branch_str = wp.branch and (" \u{2014} " .. wp.branch) or ""
        local display = string.format("[%s] %s%s", icon, wp.title, branch_str)

        return {
          value = wp,
          display = display,
          ordinal = wp.title .. " " .. (wp.description or "") .. " " .. (wp.status or ""),
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = previewers.new_buffer_previewer({
      title = "Waypoint Details",
      define_preview = function(self, entry)
        local wp = entry.value
        local lines = {
          "Title: " .. wp.title,
          "Status: " .. wp.status,
          "Branch: " .. (wp.branch or ""),
          "",
        }
        if wp.description and wp.description ~= "" then
          table.insert(lines, "Description:")
          for line in wp.description:gmatch("[^\n]+") do
            table.insert(lines, "  " .. line)
          end
          table.insert(lines, "")
        end
        if wp.reasoning and wp.reasoning ~= "" then
          table.insert(lines, "Reasoning:")
          for line in wp.reasoning:gmatch("[^\n]+") do
            table.insert(lines, "  " .. line)
          end
          table.insert(lines, "")
        end
        if wp.depends_on and #wp.depends_on > 0 then
          table.insert(lines, "Dependencies:")
          for _, dep_id in ipairs(wp.depends_on) do
            local dep = route_mod.get(dep_id)
            local dep_name = dep and dep.title or dep_id
            table.insert(lines, "  - " .. dep_name)
          end
          table.insert(lines, "")
        end
        if wp.linked_note_ids and #wp.linked_note_ids > 0 then
          table.insert(lines, "Linked Notes:")
          local note_mod = require("expedition.note")
          for _, nid in ipairs(wp.linked_note_ids) do
            local note = note_mod.get(nid)
            local preview = note and (note.body:match("^[^\n]*") or ""):sub(1, 40) or nid
            table.insert(lines, "  - " .. preview)
          end
        end
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      end,
    }),
    attach_mappings = function(_, _)
      -- No file jump for waypoints
      return true
    end,
  }):find()
end

--- Switch expedition.
--- @param opts table?
function M.expeditions(opts)
  opts = opts or {}
  local pickers, finders, conf, actions, action_state = telescope_require()

  local expedition_mod = require("expedition.expedition")
  local summaries = expedition_mod.list()

  pickers.new(opts, {
    prompt_title = "Expeditions",
    finder = finders.new_table({
      results = summaries,
      entry_maker = function(s)
        local display = string.format(
          "%s [%s] \u{2014} %d notes \u{2014} %s",
          s.name, s.status, s.note_count, s.created_at
        )
        return {
          value = s,
          display = display,
          ordinal = s.name .. " " .. s.status,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry then
          expedition_mod.load(entry.value.id)
          vim.notify("[expedition] loaded: " .. entry.value.name, vim.log.levels.INFO)
        end
      end)
      return true
    end,
  }):find()
end

--- Browse summit conditions.
--- @param opts table?
function M.conditions(opts)
  opts = opts or {}
  local pickers, finders, conf, actions, action_state = telescope_require()

  local summit_mod = require("expedition.summit")
  local conditions = summit_mod.list()

  pickers.new(opts, {
    prompt_title = "Summit Conditions",
    finder = finders.new_table({
      results = conditions,
      entry_maker = function(c)
        local icon = COND_STATUS_ICONS[c.status] or "[ ]"
        local display = string.format("%s %s", icon, c.text)
        return {
          value = c,
          display = display,
          ordinal = c.text .. " " .. c.status,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry then
          local c = entry.value
          local new_status = c.status == "met" and "open" or "met"
          local updated = summit_mod.set_status(c.id, new_status)
          if updated then
            vim.notify(
              string.format("[expedition] condition %s: %s", new_status, c.text),
              vim.log.levels.INFO
            )
          end
        end
      end)
      return true
    end,
  }):find()
end

--- Recent file visits (breadcrumbs).
--- @param opts table?
function M.breadcrumbs(opts)
  opts = opts or {}
  local pickers, finders, conf, actions, action_state = telescope_require()

  local bc_mod = require("expedition.breadcrumbs")
  local entries = bc_mod.list()
  local storage = require("expedition.storage")
  local root = storage.project_root()

  -- Reverse for most recent first
  local reversed = {}
  for i = #entries, 1, -1 do
    table.insert(reversed, entries[i])
  end

  pickers.new(opts, {
    prompt_title = "Breadcrumbs",
    finder = finders.new_table({
      results = reversed,
      entry_maker = function(bc)
        local display = string.format("%s:%d \u{2014} %s", bc.file, bc.line, bc.timestamp)
        return {
          value = bc,
          display = display,
          ordinal = bc.file,
          filename = root .. "/" .. bc.file,
          lnum = bc.line,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = conf.file_previewer(opts),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry then
          jump_to(entry.value.file, entry.value.line)
        end
      end)
      return true
    end,
  }):find()
end

return M
