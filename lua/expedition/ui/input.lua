--- Floating note input window for expedition.nvim
local M = {}

--- @type number?
local _buf = nil
--- @type number?
local _win = nil
--- @type expedition.Anchor?
local _pending_anchor = nil

--- Check if the input window is open.
--- @return boolean
function M.is_open()
  return _win ~= nil and vim.api.nvim_win_is_valid(_win)
end

--- Close the input window.
function M.close()
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_close(_win, true)
  end
  if _buf and vim.api.nvim_buf_is_valid(_buf) then
    vim.api.nvim_buf_delete(_buf, { force = true })
  end
  _win = nil
  _buf = nil
  _pending_anchor = nil
end

--- Extract #hashtags from text.
--- @param text string
--- @return string[]
local function extract_tags(text)
  local tags = {}
  local seen = {}
  for tag in text:gmatch("#(%w+)") do
    if not seen[tag] then
      table.insert(tags, tag)
      seen[tag] = true
    end
  end
  return tags
end

--- Submit the note content from the input buffer.
local function submit()
  if not _buf or not vim.api.nvim_buf_is_valid(_buf) then return end

  local lines = vim.api.nvim_buf_get_lines(_buf, 0, -1, false)
  local body = vim.fn.trim(table.concat(lines, "\n"))

  if body == "" then
    vim.notify("[expedition] empty note, cancelled", vim.log.levels.INFO)
    M.close()
    return
  end

  local tags = extract_tags(body)
  local anchor = _pending_anchor

  M.close()

  local note_mod = require("expedition.note")
  local note = note_mod.create(body, { tags = tags, anchor = anchor })

  if note then
    vim.notify("[expedition] note created", vim.log.levels.INFO)
    -- Refresh signs in the relevant buffer
    require("expedition.ui.signs").refresh_all()
    -- Refresh panel if open
    local panel = require("expedition.ui.panel")
    if panel.is_open() then
      panel.refresh()
    end
  end
end

--- Open the floating input window.
--- @param opts table? { anchor?, on_submit?, visual? }
function M.open(opts)
  opts = opts or {}

  if M.is_open() then
    M.close()
  end

  -- Capture anchor BEFORE opening the float
  if opts.anchor then
    _pending_anchor = opts.anchor
  else
    local anchor_mod = require("expedition.anchor")
    local current_buf = vim.api.nvim_get_current_buf()
    local rel = anchor_mod.relative_path(current_buf)
    if rel ~= "" then
      _pending_anchor = anchor_mod.from_cursor(current_buf, { visual = opts.visual })
    end
  end

  local config = require("expedition.config")
  local width = config.val("input.width")
  local height = config.val("input.height")
  local border = config.val("input.border")

  -- Create buffer
  _buf = vim.api.nvim_create_buf(false, true)
  vim.bo[_buf].buftype = "nofile"
  vim.bo[_buf].filetype = "markdown"
  vim.bo[_buf].bufhidden = "wipe"

  -- Calculate centered position
  local ui = vim.api.nvim_list_uis()[1]
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  -- Open float
  _win = vim.api.nvim_open_win(_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    border = border,
    title = " New Note ",
    title_pos = "center",
    style = "minimal",
  })

  vim.wo[_win].wrap = true
  vim.wo[_win].linebreak = true

  -- Buffer-local keymaps
  local buf = _buf
  vim.keymap.set("n", "<CR>", submit, { buffer = buf, desc = "Submit note" })
  vim.keymap.set("n", "q", M.close, { buffer = buf, desc = "Cancel note" })

  -- Start in insert mode
  vim.cmd("startinsert")
end

return M
