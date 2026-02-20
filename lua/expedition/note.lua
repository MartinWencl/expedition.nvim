--- Note CRUD for expedition.nvim
local types = require("expedition.types")
local storage = require("expedition.storage")
local hooks = require("expedition.hooks")
local log = require("expedition.log")
local expedition_mod = require("expedition.expedition")

local M = {}

--- Get the path to the notes.json for the active expedition.
--- @return string?
function M.notes_path()
  local active = expedition_mod.get_active()
  if not active then return nil end
  return expedition_mod.expedition_dir(active.id) .. "/notes.json"
end

--- Read all notes from disk for the active expedition.
--- @return expedition.Note[]
local function read_notes()
  local path = M.notes_path()
  if not path then return {} end
  return storage.read_json(path) or {}
end

--- Write all notes to disk for the active expedition.
--- @param notes expedition.Note[]
--- @return boolean
local function write_notes(notes)
  local path = M.notes_path()
  if not path then return false end
  return storage.write_json(path, notes)
end

--- Create a new note in the active expedition.
--- @param body string
--- @param opts table? { tags?, anchor?, meta? }
--- @return expedition.Note?
function M.create(body, opts)
  local active = expedition_mod.get_active()
  if not active then
    vim.notify("[expedition] no active expedition", vim.log.levels.ERROR)
    return nil
  end

  opts = opts or {}
  local note = types.new_note(active.id, body, opts)
  local notes = read_notes()
  table.insert(notes, note)
  write_notes(notes)

  log.append(active.id, "note.created", { note_id = note.id, body = body })
  hooks.dispatch("note.created", { note = note })

  return note
end

--- List all notes for the active expedition.
--- @return expedition.Note[]
function M.list()
  return read_notes()
end

--- Get notes for a specific file (by relative path).
--- @param rel_path string
--- @return expedition.Note[]
function M.for_file(rel_path)
  local notes = read_notes()
  local result = {}
  for _, n in ipairs(notes) do
    if n.anchor and n.anchor.file == rel_path then
      table.insert(result, n)
    end
  end
  return result
end

--- Get a note by ID.
--- @param note_id expedition.NoteId
--- @return expedition.Note?
function M.get(note_id)
  local notes = read_notes()
  for _, n in ipairs(notes) do
    if n.id == note_id then
      return n
    end
  end
  return nil
end

--- Update a note's fields.
--- @param note_id expedition.NoteId
--- @param changes table
--- @return expedition.Note?
function M.update(note_id, changes)
  local active = expedition_mod.get_active()
  if not active then return nil end

  local util = require("expedition.util")
  local notes = read_notes()
  for i, n in ipairs(notes) do
    if n.id == note_id then
      for k, v in pairs(changes) do
        n[k] = v
      end
      n.updated_at = util.timestamp()
      notes[i] = n
      write_notes(notes)

      log.append(active.id, "note.updated", { note_id = note_id, changes = changes })
      hooks.dispatch("note.updated", { note = n, changes = changes })
      return n
    end
  end
  return nil
end

--- Delete a note by ID.
--- @param note_id expedition.NoteId
--- @return boolean
function M.delete(note_id)
  local active = expedition_mod.get_active()
  if not active then return false end

  local notes = read_notes()
  for i, n in ipairs(notes) do
    if n.id == note_id then
      table.remove(notes, i)
      write_notes(notes)

      log.append(active.id, "note.deleted", { note_id = note_id })
      hooks.dispatch("note.deleted", { note_id = note_id })
      return true
    end
  end
  return false
end

return M
