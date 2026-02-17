--- Campfire chat buffer for AI brainstorming
--- Opens as a vertical split. Conversation survives close/reopen within session.
local M = {}

local util = require("expedition.util")

local _buf = nil
local _win = nil
--- @type expedition.CampfireMessage[]
local _conversation = {}
local _pending_handle = nil
local _waiting = false

local NS = vim.api.nvim_create_namespace("expedition_campfire")
local SEPARATOR = string.rep("\xe2\x94\x80", 40) -- unicode box-drawing horizontal line

--- Render the campfire buffer.
local function render()
  if not _buf or not vim.api.nvim_buf_is_valid(_buf) then return end

  vim.bo[_buf].modifiable = true
  local lines = {}
  local hl_ranges = {}

  table.insert(lines, "Campfire - Expedition Brainstorm")
  table.insert(lines, "")
  table.insert(hl_ranges, { 0, "ExpeditionPanelTitle" })

  for _, msg in ipairs(_conversation) do
    local label = msg.role == "user" and "You" or "AI"
    local label_hl = msg.role == "user" and "ExpeditionCampfireUser" or "ExpeditionPanelNote"
    local line_nr = #lines
    table.insert(lines, label .. ":")
    table.insert(hl_ranges, { line_nr, label_hl })

    for content_line in msg.content:gmatch("[^\n]+") do
      table.insert(lines, "  " .. content_line)
    end
    table.insert(lines, "")
  end

  if _waiting then
    local line_nr = #lines
    table.insert(lines, "[thinking...]")
    table.insert(hl_ranges, { line_nr, "ExpeditionCampfireThinking" })
    table.insert(lines, "")
  end

  table.insert(lines, SEPARATOR)
  table.insert(lines, "")

  vim.api.nvim_buf_set_lines(_buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(_buf, NS, 0, -1)

  for _, hl in ipairs(hl_ranges) do
    vim.api.nvim_buf_add_highlight(_buf, NS, hl[2], hl[1], 0, -1)
  end

  vim.bo[_buf].modifiable = _waiting == false

  -- Place cursor at the end for input
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_set_cursor(_win, { #lines, 0 })
  end
end

--- Get user input text (lines below separator).
--- @return string
local function get_input()
  if not _buf or not vim.api.nvim_buf_is_valid(_buf) then return "" end
  local lines = vim.api.nvim_buf_get_lines(_buf, 0, -1, false)

  -- Find separator line
  local sep_line = nil
  for i = #lines, 1, -1 do
    if lines[i] == SEPARATOR then
      sep_line = i
      break
    end
  end

  if not sep_line then return "" end

  local input_lines = {}
  for i = sep_line + 1, #lines do
    table.insert(input_lines, lines[i])
  end

  return vim.fn.trim(table.concat(input_lines, "\n"))
end

--- Send the user's message.
local function send()
  if _waiting then
    vim.notify("[expedition] Waiting for AI response...", vim.log.levels.WARN)
    return
  end

  local input = get_input()
  if input == "" then return end

  -- Add user message
  table.insert(_conversation, {
    role = "user",
    content = input,
    timestamp = util.timestamp(),
  })

  _waiting = true
  render()

  -- Build prompt and call AI
  local prompt_mod = require("expedition.ai.prompt")
  local provider = require("expedition.ai.provider")

  local prompt_text, system = prompt_mod.build_campfire_prompt(_conversation)

  _pending_handle = provider.call({
    prompt = prompt_text,
    system = system,
    on_success = function(response)
      _waiting = false
      _pending_handle = nil
      response = vim.fn.trim(response)
      if response ~= "" then
        table.insert(_conversation, {
          role = "assistant",
          content = response,
          timestamp = util.timestamp(),
        })
      end
      render()
    end,
    on_error = function(err)
      _waiting = false
      _pending_handle = nil
      vim.notify("[expedition] Campfire AI error: " .. err, vim.log.levels.ERROR)
      render()
    end,
  })
end

--- Promote the last AI response to a note tagged #campfire.
local function promote_to_note()
  -- Find last assistant message
  local last_ai = nil
  for i = #_conversation, 1, -1 do
    if _conversation[i].role == "assistant" then
      last_ai = _conversation[i]
      break
    end
  end

  if not last_ai then
    vim.notify("[expedition] No AI response to promote", vim.log.levels.WARN)
    return
  end

  local note_mod = require("expedition.note")
  local note = note_mod.create(last_ai.content, { tags = { "campfire" } })
  if note then
    vim.notify("[expedition] Promoted AI response to note", vim.log.levels.INFO)
  end
end

--- Close the campfire buffer (conversation preserved).
function M.close()
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_close(_win, true)
  end
  _win = nil
  -- Don't delete _buf reference — we'll check validity on reopen
  _buf = nil
end

--- Check if campfire is currently open.
--- @return boolean
function M.is_open()
  return _win ~= nil and vim.api.nvim_win_is_valid(_win)
end

--- Toggle the campfire buffer.
function M.toggle()
  if M.is_open() then
    M.close()
    return
  end
  M.open()
end

--- Open the campfire buffer.
function M.open()
  if M.is_open() then
    vim.api.nvim_set_current_win(_win)
    return
  end

  _buf = vim.api.nvim_create_buf(false, true)
  vim.bo[_buf].buftype = "nofile"
  vim.bo[_buf].bufhidden = "hide"
  vim.bo[_buf].filetype = "markdown"
  vim.bo[_buf].swapfile = false

  -- Open as vertical split
  vim.cmd("vsplit")
  _win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(_win, _buf)
  vim.api.nvim_win_set_width(_win, 50)
  vim.wo[_win].wrap = true
  vim.wo[_win].number = false
  vim.wo[_win].relativenumber = false
  vim.wo[_win].signcolumn = "no"

  -- Set up keymaps
  local map_opts = { buffer = _buf, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", send, map_opts)
  vim.keymap.set("n", "q", M.close, map_opts)
  vim.keymap.set("n", "gn", promote_to_note, map_opts)

  render()
end

--- Reset conversation history.
function M.reset()
  if _pending_handle then
    _pending_handle.cancel()
    _pending_handle = nil
  end
  _waiting = false
  _conversation = {}
  if _buf and vim.api.nvim_buf_is_valid(_buf) then
    render()
  end
end

return M
