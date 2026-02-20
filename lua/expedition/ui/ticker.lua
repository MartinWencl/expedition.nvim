--- Floating ticker widget for expedition.nvim
--- Shows route progress, active waypoint, next-up list, and transient event flashes.
--- Opt-in via config: ticker.enabled = true
local M = {}

local hooks = require("expedition.hooks")
local config = require("expedition.config")

--- @type number?
local _buf = nil
--- @type number?
local _win = nil
--- @type { text: string, timer: uv_timer_t }[]
local _flashes = {}
--- @type boolean
local _registered = false

--- Ensure the scratch buffer exists.
local function ensure_buf()
  if _buf and vim.api.nvim_buf_is_valid(_buf) then return end
  _buf = vim.api.nvim_create_buf(false, true)
  vim.bo[_buf].buftype = "nofile"
  vim.bo[_buf].filetype = "expedition-ticker"
  vim.bo[_buf].bufhidden = "wipe"
end

--- Open or reposition the floating window.
--- @param height number
local function open_win(height)
  local width = 40
  local opts = {
    relative = "editor",
    anchor = "SE",
    row = vim.o.lines - 2,
    col = vim.o.columns,
    width = width,
    height = height,
    style = "minimal",
    border = "none",
    focusable = false,
    noautocmd = true,
    zindex = 40,
  }
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_set_config(_win, opts)
  else
    _win = vim.api.nvim_open_win(_buf, false, opts)
    vim.wo[_win].winblend = 20
    vim.wo[_win].winhighlight = "Normal:ExpeditionTicker,FloatBorder:ExpeditionTicker"
  end
end

--- Close the floating window.
function M.hide()
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_close(_win, true)
  end
  _win = nil
end

--- Add a transient flash message that fades after timeout.
--- @param text string
function M.flash(text)
  local timeout = config.val("ticker.event_timeout") or 4000
  local entry = { text = text, timer = nil }
  table.insert(_flashes, entry)

  entry.timer = vim.defer_fn(function()
    for i, f in ipairs(_flashes) do
      if f == entry then
        table.remove(_flashes, i)
        break
      end
    end
    M.render()
  end, timeout)

  M.render()
end

--- Render the ticker content. Assembles lines, resizes window, sets buffer.
function M.render()
  if not config.val("ticker.enabled") then return end

  local sl = require("expedition.statusline")
  if not sl.is_active() then
    M.hide()
    return
  end

  local lines = {}
  local show = config.val("ticker.show") or {}

  if show.active_waypoint then
    local wp = sl.active_waypoint()
    if wp ~= "" then table.insert(lines, wp) end
  end

  if show.progress then
    local p = sl.progress()
    if p ~= "" then table.insert(lines, p) end
  end

  if show.next_up and show.next_up > 0 then
    local ok, route_mod = pcall(require, "expedition.route")
    if ok then
      local ready = route_mod.get_ready()
      for i = 1, math.min(show.next_up, #ready) do
        table.insert(lines, "  " .. ready[i].title)
      end
    end
  end

  if show.events then
    for _, flash in ipairs(_flashes) do
      table.insert(lines, flash.text)
    end
  end

  if #lines == 0 then
    M.hide()
    return
  end

  -- Truncate lines to fit window width
  local width = 40
  for i, line in ipairs(lines) do
    if vim.fn.strdisplaywidth(line) > width then
      -- Truncate respecting multibyte chars
      local truncated = vim.fn.strcharpart(line, 0, width - 1)
      while vim.fn.strdisplaywidth(truncated) > width - 1 do
        truncated = vim.fn.strcharpart(truncated, 0, vim.fn.strchars(truncated) - 1)
      end
      lines[i] = truncated .. "\u{2026}"
    end
  end

  ensure_buf()
  open_win(#lines)
  vim.bo[_buf].modifiable = true
  vim.api.nvim_buf_set_lines(_buf, 0, -1, false, lines)
  vim.bo[_buf].modifiable = false
end

--- Schedule a debounced render.
local _render_scheduled = false
local function schedule_render()
  if _render_scheduled then return end
  _render_scheduled = true
  vim.schedule(function()
    _render_scheduled = false
    M.render()
  end)
end

--- Register the ticker — subscribe to hooks and set up autocmds.
--- Called from init.lua:setup() when ticker.enabled.
function M.register()
  if _registered then return end
  _registered = true

  -- Re-render on data changes
  local data_events = {
    "expedition.activated", "expedition.updated",
    "waypoint.created", "waypoint.updated", "waypoint.status_changed", "waypoint.deleted",
    "condition.created", "condition.updated", "condition.status_changed", "condition.deleted",
  }
  for _, event in ipairs(data_events) do
    hooks.on(event, schedule_render)
  end

  -- Flash on interesting events
  hooks.on("waypoint.status_changed", function(p)
    if p and p.waypoint and p.to then
      M.flash("Waypoint " .. p.to .. ": " .. p.waypoint.title)
    end
  end)

  hooks.on("note.drift_detected", function(p)
    if p and p.note and p.note.anchor then
      M.flash("Drift detected: " .. p.note.anchor.file)
    end
  end)

  hooks.on("condition.status_changed", function(p)
    if p and p.condition and p.to then
      M.flash("Condition " .. p.to .. ": " .. p.condition.text)
    end
  end)

  -- Reposition on resize
  local group = vim.api.nvim_create_augroup("ExpeditionTicker", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = schedule_render,
  })
end

--- Reset module state (for testing).
function M._reset()
  M.hide()
  for _, f in ipairs(_flashes) do
    if f.timer then
      pcall(function() f.timer:stop() end)
    end
  end
  _flashes = {}
  _buf = nil
  _win = nil
  _registered = false
  _render_scheduled = false
end

return M
