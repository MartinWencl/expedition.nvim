--- Gutter extmarks (signs) for expedition.nvim
local M = {}

local _ns = nil

--- Get or create the namespace for expedition signs.
--- @return number
function M.namespace()
  if not _ns then
    _ns = vim.api.nvim_create_namespace("expedition_signs")
  end
  return _ns
end

--- Clear all expedition extmarks in a buffer.
--- @param buf number
function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.namespace(), 0, -1)
end

--- Place extmarks for notes anchored in the given buffer.
--- @param buf number
function M.refresh(buf)
  local config = require("expedition.config")
  if not config.val("signs.enabled") then return end

  local anchor_mod = require("expedition.anchor")
  local note_mod = require("expedition.note")

  local rel_path = anchor_mod.relative_path(buf)
  if rel_path == "" then return end

  local notes = note_mod.for_file(rel_path)
  M.clear(buf)

  local ns = M.namespace()
  local icon = config.val("signs.icon")
  local priority = config.val("signs.priority")

  for _, note in ipairs(notes) do
    if note.anchor then
      local line = note.anchor.line - 1 -- extmarks are 0-indexed
      local total = vim.api.nvim_buf_line_count(buf)
      if line >= 0 and line < total then
        local hl = "ExpeditionNote"
        -- Check drift if we have a snapshot
        if note.anchor.snapshot_hash and note.anchor.snapshot_hash ~= "" then
          local matches = anchor_mod.check_drift(note.anchor, buf)
          if not matches then
            hl = "ExpeditionNoteDrifted"
          end
        end

        vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
          sign_text = icon,
          sign_hl_group = hl,
          priority = priority,
        })
      end
    end
  end
end

--- Refresh signs in all visible buffers.
function M.refresh_all()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local bt = vim.bo[buf].buftype
    if bt == "" then
      M.refresh(buf)
    end
  end
end

--- Jump to the next note sign in the current buffer.
function M.jump_next()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] -- 1-indexed
  local ns = M.namespace()

  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { line, 0 }, { -1, -1 }, {})
  if #marks > 0 then
    local mark_line = marks[1][2] + 1 -- convert to 1-indexed
    vim.api.nvim_win_set_cursor(0, { mark_line, 0 })
    return
  end

  -- Wrap around to the beginning
  local all_marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  if #all_marks > 0 then
    local mark_line = all_marks[1][2] + 1
    vim.api.nvim_win_set_cursor(0, { mark_line, 0 })
  end
end

--- Jump to the previous note sign in the current buffer.
function M.jump_prev()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 2 -- 0-indexed, one line above cursor
  local ns = M.namespace()

  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { math.max(0, line), 0 }, 0, {})
  if #marks > 0 then
    local mark_line = marks[1][2] + 1
    vim.api.nvim_win_set_cursor(0, { mark_line, 0 })
    return
  end

  -- Wrap around to the end
  local all_marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  if #all_marks > 0 then
    local mark_line = all_marks[#all_marks][2] + 1
    vim.api.nvim_win_set_cursor(0, { mark_line, 0 })
  end
end

return M
