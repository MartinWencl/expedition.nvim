--- Centralized file I/O for expedition.nvim
--- No other module should touch io.open directly.
local util = require("expedition.util")

local M = {}

--- Find the project root (git root or cwd).
--- @return string
function M.project_root()
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  if vim.v.shell_error == 0 and git_root and git_root ~= "" then
    return vim.fn.fnamemodify(git_root, ":p"):gsub("/$", "")
  end
  return vim.fn.getcwd()
end

--- Generate a stable project ID from the root path.
--- @param root string
--- @return string
function M.project_id(root)
  return util.hash(root)
end

--- Ensure the project data directory exists and return its path.
--- @param project_id string
--- @return string
function M.ensure_project_dir(project_id)
  local config = require("expedition.config")
  local dir = config.get().data_dir .. "/" .. project_id
  vim.fn.mkdir(dir, "p")
  return dir
end

--- Ensure an expedition subdirectory exists and return its path.
--- @param project_id string
--- @param expedition_id string
--- @return string
function M.ensure_expedition_dir(project_id, expedition_id)
  local project_dir = M.ensure_project_dir(project_id)
  local dir = project_dir .. "/expeditions/" .. expedition_id
  vim.fn.mkdir(dir, "p")
  return dir
end

--- Read and decode a JSON file.
--- @param path string
--- @return table?, string? data or nil+error
function M.read_json(path)
  local f, err = io.open(path, "r")
  if not f then
    return nil, err
  end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then
    return nil, "empty file"
  end
  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    return nil, "json decode error: " .. tostring(data)
  end
  return data, nil
end

--- Atomically write a JSON file (write to .tmp then rename).
--- @param path string
--- @param data table
--- @return boolean, string?
function M.write_json(path, data)
  local encoded = vim.json.encode(data)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "w")
  if not f then
    return false, "write error: " .. tostring(err)
  end
  f:write(encoded)
  f:close()
  local ok, rename_err = os.rename(tmp, path)
  if not ok then
    os.remove(tmp)
    return false, "rename error: " .. tostring(rename_err)
  end
  return true, nil
end

--- Append a single JSON object as a line to a JSONL file.
--- @param path string
--- @param entry table
--- @return boolean
function M.append_jsonl(path, entry)
  local f, err = io.open(path, "a")
  if not f then
    vim.notify("[expedition] log write error: " .. tostring(err), vim.log.levels.WARN)
    return false
  end
  f:write(vim.json.encode(entry) .. "\n")
  f:close()
  return true
end

--- Read all entries from a JSONL file.
--- @param path string
--- @return table[]
function M.read_jsonl(path)
  local entries = {}
  local f = io.open(path, "r")
  if not f then
    return entries
  end
  for line in f:lines() do
    if line ~= "" then
      local ok, entry = pcall(vim.json.decode, line)
      if ok then
        table.insert(entries, entry)
      end
    end
  end
  f:close()
  return entries
end

--- List subdirectory names within a directory.
--- @param dir string
--- @return string[]
function M.list_dirs(dir)
  local dirs = {}
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return dirs
  end
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then break end
    if type == "directory" then
      table.insert(dirs, name)
    end
  end
  return dirs
end

--- Delete a file.
--- @param path string
--- @return boolean
function M.delete_file(path)
  local ok = os.remove(path)
  return ok ~= nil
end

--- Write project metadata file.
--- @param project_id string
--- @param root string
function M.write_project_meta(project_id, root)
  local dir = M.ensure_project_dir(project_id)
  local meta_path = dir .. "/meta.json"
  -- Only write if it doesn't exist yet
  local f = io.open(meta_path, "r")
  if f then
    f:close()
    return
  end
  M.write_json(meta_path, {
    root = root,
    name = vim.fn.fnamemodify(root, ":t"),
  })
end

return M
