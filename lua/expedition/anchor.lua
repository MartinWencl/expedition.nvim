--- Anchoring logic: treesitter symbol resolution, snapshots, relative paths
local types = require("expedition.types")
local util = require("expedition.util")
local storage = require("expedition.storage")

local M = {}

--- Get the project-relative path for a buffer.
--- @param buf number? buffer handle (0 or nil for current)
--- @return string
function M.relative_path(buf)
  buf = buf or 0
  local abs = vim.api.nvim_buf_get_name(buf)
  if abs == "" then return "" end
  local root = storage.project_root()
  -- Strip root prefix to get relative path
  if abs:sub(1, #root) == root then
    local rel = abs:sub(#root + 2) -- +2 to skip the trailing /
    return rel
  end
  return abs
end

--- Resolve the nearest treesitter symbol (function/class/method) at a position.
--- @param buf number
--- @param line number 1-indexed
--- @param col number? 0-indexed, defaults to 0
--- @return string? symbol string like "function:name"
function M.resolve_symbol(buf, line, col)
  col = col or 0
  local config = require("expedition.config")
  if not config.val("anchor.use_treesitter") then
    return nil
  end

  local ok, node = pcall(vim.treesitter.get_node, {
    bufnr = buf,
    pos = { line - 1, col }, -- treesitter is 0-indexed
  })
  if not ok or not node then
    return nil
  end

  local target_types = {
    function_declaration = "function",
    function_definition = "function",
    method_definition = "method",
    method_declaration = "method",
    class_declaration = "class",
    class_definition = "class",
    local_function = "function",
    function_item = "function", -- Rust
    impl_item = "impl",        -- Rust
  }

  local current = node
  while current do
    local ntype = current:type()
    local kind = target_types[ntype]
    if kind then
      -- Try to find the name child
      local name_node = current:field("name")[1]
      if name_node then
        local name = vim.treesitter.get_node_text(name_node, buf)
        return kind .. ":" .. name
      end
    end
    current = current:parent()
  end

  return nil
end

--- Capture a snapshot of lines around a position.
--- @param buf number
--- @param line number 1-indexed
--- @param context number number of lines above and below
--- @return string hash, string[] lines
function M.snapshot(buf, line, context)
  local total = vim.api.nvim_buf_line_count(buf)
  local start_line = math.max(0, line - 1 - context)
  local end_line = math.min(total, line - 1 + context + 1)
  local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)
  local hash = util.hash_lines(lines)
  return hash, lines
end

--- Check if an anchor's snapshot still matches the current buffer content.
--- @param anchor expedition.Anchor
--- @param buf number
--- @return boolean matches, string current_hash
function M.check_drift(anchor, buf)
  local config = require("expedition.config")
  local context = config.val("anchor.snapshot_context") or 3
  local current_hash, _ = M.snapshot(buf, anchor.line, context)
  return current_hash == anchor.snapshot_hash, current_hash
end

--- Create an anchor from the current cursor position (or visual selection).
--- @param buf number? buffer handle (0 or nil for current)
--- @param opts table? { visual?, end_line? }
--- @return expedition.Anchor
function M.from_cursor(buf, opts)
  buf = buf or 0
  opts = opts or {}

  local config = require("expedition.config")
  local context = config.val("anchor.snapshot_context") or 3

  local file = M.relative_path(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local end_line = opts.end_line

  -- Detect visual selection range
  if opts.visual then
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    line = start_pos[2]
    end_line = end_pos[2]
  end

  local symbol = M.resolve_symbol(buf, line)
  local hash, snapshot_lines = M.snapshot(buf, line, context)

  return types.new_anchor(file, line, {
    end_line = end_line,
    symbol = symbol,
    snapshot_hash = hash,
    snapshot_lines = snapshot_lines,
  })
end

return M
