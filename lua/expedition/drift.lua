--- Drift detection engine for expedition.nvim
--- Checks anchored notes for code changes on buf_write events.
local anchor = require("expedition.anchor")
local note_mod = require("expedition.note")
local hooks = require("expedition.hooks")
local log = require("expedition.log")

local M = {}

--- Subscribe to buf_write events for drift checking.
function M.register()
  hooks.on("buf_write", function(payload)
    M.check(payload)
  end)
end

--- Check all anchored notes on the written file for drift.
--- @param payload { buf: number, file: string }
function M.check(payload)
  local expedition_mod = require("expedition.expedition")
  local active = expedition_mod.get_active()
  if not active then return end

  local rel_path = anchor.relative_path(payload.buf)
  if rel_path == "" then return end

  local notes = note_mod.for_file(rel_path)
  for _, n in ipairs(notes) do
    if n.anchor and n.anchor.snapshot_hash and n.anchor.snapshot_hash ~= "" then
      local matches, current_hash = anchor.check_drift(n.anchor, payload.buf)
      if not matches and n.drift_status ~= "drifted" then
        note_mod.update(n.id, { drift_status = "drifted" })
        hooks.dispatch("note.drift_detected", {
          note = n,
          old_hash = n.anchor.snapshot_hash,
          new_hash = current_hash,
        })
        log.append(active.id, "note.drift_detected", {
          note_id = n.id,
          file = rel_path,
        })
      elseif matches and n.drift_status == "drifted" then
        note_mod.update(n.id, { drift_status = "ok" })
      end
    end
  end
end

--- Acknowledge drift on a specific note: re-snapshot and clear drift status.
--- @param note_id expedition.NoteId
function M.acknowledge(note_id)
  local expedition_mod = require("expedition.expedition")
  local active = expedition_mod.get_active()
  if not active then return end

  local n = note_mod.get(note_id)
  if not n or not n.anchor then return end

  local config = require("expedition.config")
  local context = config.val("anchor.snapshot_context") or 3

  -- Find buffer for this file
  local storage = require("expedition.storage")
  local root = storage.project_root()
  local abs_path = root .. "/" .. n.anchor.file

  local buf = vim.fn.bufnr(abs_path)
  if buf == -1 then
    vim.notify("[expedition] buffer not loaded for " .. n.anchor.file, vim.log.levels.WARN)
    return
  end

  local new_hash, new_lines = anchor.snapshot(buf, n.anchor.line, context)
  local new_anchor = vim.tbl_extend("force", n.anchor, {
    snapshot_hash = new_hash,
    snapshot_lines = new_lines,
  })

  note_mod.update(note_id, { anchor = new_anchor, drift_status = "ok" })
  hooks.dispatch("note.drift_acknowledged", { note_id = note_id })
  log.append(active.id, "note.drift_acknowledged", { note_id = note_id })
  vim.notify("[expedition] drift acknowledged for note " .. note_id, vim.log.levels.INFO)
end

--- Acknowledge all drifted notes in the current buffer.
function M.acknowledge_buffer()
  local expedition_mod = require("expedition.expedition")
  local active = expedition_mod.get_active()
  if not active then return end

  local buf = vim.api.nvim_get_current_buf()
  local rel_path = anchor.relative_path(buf)
  if rel_path == "" then return end

  local notes = note_mod.for_file(rel_path)
  local count = 0
  for _, n in ipairs(notes) do
    if n.drift_status == "drifted" then
      M.acknowledge(n.id)
      count = count + 1
    end
  end

  if count == 0 then
    vim.notify("[expedition] no drifted notes in this buffer", vim.log.levels.INFO)
  else
    vim.notify("[expedition] acknowledged " .. count .. " drifted note(s)", vim.log.levels.INFO)
  end
end

return M
