--- Propose-approve buffer for reviewing AI route proposals
--- Opens as a horizontal split at the bottom.
local M = {}

local _buf = nil
local _win = nil
--- @type expedition.AiProposal?
local _proposal = nil
local _statuses = {} -- index → "accepted"|"rejected"

local NS = vim.api.nvim_create_namespace("expedition_propose")

--- Render the proposal buffer contents.
local function render()
  if not _buf or not vim.api.nvim_buf_is_valid(_buf) then return end
  if not _proposal then return end

  vim.bo[_buf].modifiable = true
  local lines = {}
  local hl_ranges = {}

  table.insert(lines, "Expedition Route Proposal")
  table.insert(lines, "")
  if _proposal.summary ~= "" then
    table.insert(lines, _proposal.summary)
    table.insert(lines, "")
  end
  table.insert(lines, "a = accept  x = reject  A = accept all  C = confirm  q = cancel")
  table.insert(lines, string.rep("-", 60))
  table.insert(lines, "")

  for i, wp in ipairs(_proposal.waypoints) do
    local status = _statuses[i] or "accepted"
    local marker, hl_group
    if status == "accepted" then
      marker = "[+]"
      hl_group = "ExpeditionProposalAccepted"
    else
      marker = "[-]"
      hl_group = "ExpeditionProposalRejected"
    end

    local line_nr = #lines
    local title_line = marker .. " " .. wp.title
    table.insert(lines, title_line)
    table.insert(hl_ranges, { line_nr, 0, #marker, hl_group })

    if wp.description ~= "" then
      table.insert(lines, "    " .. wp.description)
    end
    if wp.reasoning ~= "" then
      table.insert(lines, "    Reasoning: " .. wp.reasoning)
    end
    if #wp.depends_on_titles > 0 then
      table.insert(lines, "    Depends on: " .. table.concat(wp.depends_on_titles, ", "))
    end
    table.insert(lines, "")
  end

  vim.api.nvim_buf_set_lines(_buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(_buf, NS, 0, -1)

  for _, hl in ipairs(hl_ranges) do
    vim.api.nvim_buf_add_highlight(_buf, NS, hl[4], hl[1], hl[2], hl[3])
  end

  vim.bo[_buf].modifiable = false
end

--- Find which waypoint index the cursor is on.
--- @return number? index (1-based)
local function waypoint_at_cursor()
  if not _buf or not _proposal then return nil end
  local cursor_line = vim.api.nvim_win_get_cursor(_win)[1] -- 1-indexed
  local lines = vim.api.nvim_buf_get_lines(_buf, 0, -1, false)

  -- Walk backwards from cursor to find the nearest [+] or [-] marker
  for row = cursor_line, 1, -1 do
    local line = lines[row]
    if line:match("^%[%+%]") or line:match("^%[%-%]") then
      -- Count which waypoint this is
      local idx = 0
      for r = 1, row do
        if lines[r]:match("^%[%+%]") or lines[r]:match("^%[%-%]") then
          idx = idx + 1
        end
      end
      return idx
    end
  end
  return nil
end

--- Confirm: create accepted waypoints via route.create_waypoint().
local function confirm()
  if not _proposal then return end

  local route = require("expedition.route")
  local accepted = {}

  -- First pass: create all accepted waypoints (no deps yet)
  for i, wp in ipairs(_proposal.waypoints) do
    if (_statuses[i] or "accepted") == "accepted" then
      local created = route.create_waypoint({
        title = wp.title,
        description = wp.description,
        reasoning = wp.reasoning,
      })
      if created then
        accepted[wp.title] = created.id
      end
    end
  end

  -- Second pass: wire dependencies by resolving titles to IDs
  local all_waypoints = route.list()
  local title_to_id = {}
  for _, w in ipairs(all_waypoints) do
    title_to_id[w.title] = w.id
  end

  for i, wp in ipairs(_proposal.waypoints) do
    if (_statuses[i] or "accepted") == "accepted" and accepted[wp.title] then
      for _, dep_title in ipairs(wp.depends_on_titles) do
        local dep_id = title_to_id[dep_title]
        if dep_id then
          route.add_dependency(accepted[wp.title], dep_id)
        end
      end
    end
  end

  local count = vim.tbl_count(accepted)
  M.close()
  vim.notify("[expedition] Created " .. count .. " waypoint(s) from proposal", vim.log.levels.INFO)

  -- Refresh panel if open
  local ok, panel = pcall(require, "expedition.ui.panel")
  if ok and panel.is_open then
    panel.refresh()
  end
end

--- Close the propose buffer.
function M.close()
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_close(_win, true)
  end
  if _buf and vim.api.nvim_buf_is_valid(_buf) then
    vim.api.nvim_buf_delete(_buf, { force = true })
  end
  _win = nil
  _buf = nil
  _proposal = nil
  _statuses = {}
end

--- Open the propose buffer with a proposal.
--- @param proposal expedition.AiProposal
function M.open(proposal)
  -- Close any existing propose buffer
  M.close()

  _proposal = proposal
  _statuses = {}
  for i = 1, #proposal.waypoints do
    _statuses[i] = "accepted"
  end

  _buf = vim.api.nvim_create_buf(false, true)
  vim.bo[_buf].buftype = "nofile"
  vim.bo[_buf].bufhidden = "wipe"
  vim.bo[_buf].filetype = "expedition-propose"

  -- Open as horizontal split at bottom
  vim.cmd("botright split")
  _win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(_win, _buf)
  vim.api.nvim_win_set_height(_win, math.min(#proposal.waypoints * 5 + 8, 25))

  -- Set up keymaps
  local map_opts = { buffer = _buf, nowait = true, silent = true }

  vim.keymap.set("n", "a", function()
    local idx = waypoint_at_cursor()
    if idx then
      _statuses[idx] = "accepted"
      render()
    end
  end, map_opts)

  vim.keymap.set("n", "x", function()
    local idx = waypoint_at_cursor()
    if idx then
      _statuses[idx] = "rejected"
      render()
    end
  end, map_opts)

  vim.keymap.set("n", "A", function()
    for i = 1, #_proposal.waypoints do
      _statuses[i] = "accepted"
    end
    render()
  end, map_opts)

  vim.keymap.set("n", "C", confirm, map_opts)
  vim.keymap.set("n", "q", M.close, map_opts)

  render()
end

return M
