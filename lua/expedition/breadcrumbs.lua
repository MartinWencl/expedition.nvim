--- Passive breadcrumb tracking for expedition.nvim
--- Records BufEnter events as breadcrumbs for later promotion to notes.
local config = require("expedition.config")
local storage = require("expedition.storage")
local types = require("expedition.types")
local anchor = require("expedition.anchor")

local M = {}

--- Get the path to breadcrumbs.json for the active expedition.
--- @return string?
local function breadcrumbs_path()
  local expedition_mod = require("expedition.expedition")
  local active = expedition_mod.get_active()
  if not active then return nil end
  return expedition_mod.expedition_dir(active.id) .. "/breadcrumbs.json"
end

--- Read breadcrumbs from disk.
--- @return expedition.Breadcrumb[]
local function read_breadcrumbs()
  local path = breadcrumbs_path()
  if not path then return {} end
  local data = storage.read_json(path)
  if not data then return {} end
  if not data[1] and next(data) == nil then return {} end
  return data
end

--- Write breadcrumbs to disk.
--- @param breadcrumbs expedition.Breadcrumb[]
--- @return boolean
local function write_breadcrumbs(breadcrumbs)
  local path = breadcrumbs_path()
  if not path then return false end
  return storage.write_json(path, breadcrumbs)
end

--- Register the BufEnter autocmd for breadcrumb tracking.
function M.register()
  local group = vim.api.nvim_create_augroup("ExpeditionBreadcrumbs", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      if not config.val("breadcrumbs.enabled") then return end
      M.record(ev.buf)
    end,
  })
end

--- Record a breadcrumb for the given buffer.
--- @param buf number
function M.record(buf)
  if vim.bo[buf].buftype ~= "" then return end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return end

  local expedition_mod = require("expedition.expedition")
  if not expedition_mod.get_active() then return end

  local rel_path = anchor.relative_path(buf)
  if rel_path == "" then return end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  -- Dedup: skip if last entry is same file+line
  local breadcrumbs = read_breadcrumbs()
  if #breadcrumbs > 0 then
    local last = breadcrumbs[#breadcrumbs]
    if last.file == rel_path and last.line == line then
      return
    end
  end

  local bc = types.new_breadcrumb(rel_path, line)
  table.insert(breadcrumbs, bc)

  -- Trim to max_entries
  local max = config.val("breadcrumbs.max_entries") or 1000
  while #breadcrumbs > max do
    table.remove(breadcrumbs, 1)
  end

  write_breadcrumbs(breadcrumbs)
end

--- List breadcrumbs, optionally the last n entries.
--- @param n number?
--- @return expedition.Breadcrumb[]
function M.list(n)
  local breadcrumbs = read_breadcrumbs()
  if not n or n >= #breadcrumbs then
    return breadcrumbs
  end
  local result = {}
  for i = #breadcrumbs - n + 1, #breadcrumbs do
    table.insert(result, breadcrumbs[i])
  end
  return result
end

--- Promote a breadcrumb to a note by index (1-based from end of list).
--- @param index number 1-based index into the list
function M.promote(index)
  local breadcrumbs = read_breadcrumbs()
  if index < 1 or index > #breadcrumbs then
    vim.notify("[expedition] invalid breadcrumb index: " .. index, vim.log.levels.ERROR)
    return
  end

  local bc = breadcrumbs[index]
  local root = storage.project_root()
  local abs_path = root .. "/" .. bc.file

  -- Load or find the buffer
  local buf = vim.fn.bufnr(abs_path)
  if buf == -1 then
    vim.cmd("edit " .. vim.fn.fnameescape(abs_path))
    buf = vim.api.nvim_get_current_buf()
  end

  -- Build anchor
  local conf = config.get()
  local context = conf.anchor.snapshot_context or 3
  local hash, snapshot_lines = anchor.snapshot(buf, bc.line, context)
  local symbol = anchor.resolve_symbol(buf, bc.line)

  local anchor_obj = types.new_anchor(bc.file, bc.line, {
    symbol = symbol,
    snapshot_hash = hash,
    snapshot_lines = snapshot_lines,
  })

  vim.ui.input({ prompt = "Note body: " }, function(body)
    if not body or body == "" then return end

    local note_mod = require("expedition.note")
    local tags = {}
    local seen = {}
    for tag in body:gmatch("#(%w+)") do
      if not seen[tag] then
        table.insert(tags, tag)
        seen[tag] = true
      end
    end

    local note = note_mod.create(body, { tags = tags, anchor = anchor_obj })
    if note then
      vim.notify("[expedition] breadcrumb promoted to note", vim.log.levels.INFO)
      require("expedition.ui.signs").refresh_all()
    end
  end)
end

return M
