--- Data model constructors and LuaCATS annotations for expedition.nvim
local util = require("expedition.util")

local M = {}

--- @class expedition.Expedition
--- @field id string
--- @field name string
--- @field description string
--- @field created_at string ISO 8601
--- @field updated_at string
--- @field status "active"|"paused"|"completed"|"archived"
--- @field meta table freeform extension point

--- @class expedition.ExpeditionSummary
--- @field id string
--- @field name string
--- @field status "active"|"paused"|"completed"|"archived"
--- @field created_at string
--- @field note_count number

--- @class expedition.Note
--- @field id string
--- @field expedition_id string
--- @field body string
--- @field tags string[]
--- @field anchor expedition.Anchor?
--- @field created_at string
--- @field updated_at string
--- @field meta table Phase 2: { waypoint_id = "..." }

--- @class expedition.Anchor
--- @field file string project-relative path
--- @field line number 1-indexed
--- @field end_line number? for visual selection ranges
--- @field symbol string? e.g. "function:parse_config"
--- @field snapshot_hash string
--- @field snapshot_lines string[]

--- @class expedition.Waypoint
--- @field id string
--- @field title string
--- @field description string
--- @field status "blocked"|"ready"|"active"|"done"|"abandoned"
--- @field depends_on string[]         -- waypoint IDs
--- @field reasoning string
--- @field linked_note_ids string[]
--- @field branch string
--- @field created_at string
--- @field updated_at string

--- @class expedition.LogEntry
--- @field timestamp string
--- @field event string e.g. "expedition.created", "note.created"
--- @field expedition_id string
--- @field data table

--- Create a new Expedition object.
--- @param name string
--- @param opts table?
--- @return expedition.Expedition
function M.new_expedition(name, opts)
  opts = opts or {}
  local now = util.timestamp()
  return {
    id = util.id(),
    name = name,
    description = opts.description or "",
    created_at = now,
    updated_at = now,
    status = opts.status or "active",
    meta = opts.meta or {},
  }
end

--- Create a new Note object.
--- @param expedition_id string
--- @param body string
--- @param opts table?
--- @return expedition.Note
function M.new_note(expedition_id, body, opts)
  opts = opts or {}
  local now = util.timestamp()
  return {
    id = util.id(),
    expedition_id = expedition_id,
    body = body,
    tags = opts.tags or {},
    anchor = opts.anchor or nil,
    created_at = now,
    updated_at = now,
    meta = opts.meta or {},
  }
end

--- Create a new Anchor object.
--- @param file string project-relative path
--- @param line number 1-indexed
--- @param opts table?
--- @return expedition.Anchor
function M.new_anchor(file, line, opts)
  opts = opts or {}
  return {
    file = file,
    line = line,
    end_line = opts.end_line,
    symbol = opts.symbol,
    snapshot_hash = opts.snapshot_hash or "",
    snapshot_lines = opts.snapshot_lines or {},
  }
end

--- Create a new Waypoint object.
--- @param title string
--- @param opts table?
--- @return expedition.Waypoint
function M.new_waypoint(title, opts)
  opts = opts or {}
  local now = util.timestamp()
  return {
    id = util.id(),
    title = title,
    description = opts.description or "",
    status = opts.status or "ready",
    depends_on = opts.depends_on or {},
    reasoning = opts.reasoning or "",
    linked_note_ids = opts.linked_note_ids or {},
    branch = opts.branch or "main",
    created_at = now,
    updated_at = now,
  }
end

--- @class expedition.ProposedWaypoint
--- @field title string
--- @field description string
--- @field reasoning string
--- @field depends_on_titles string[]

--- @class expedition.AiProposal
--- @field waypoints expedition.ProposedWaypoint[]
--- @field summary string

--- @class expedition.CampfireMessage
--- @field role "user"|"assistant"
--- @field content string
--- @field timestamp string

--- @class expedition.SummitEvaluation
--- @field ready boolean
--- @field confidence number
--- @field reasoning string
--- @field remaining string[]

--- @class expedition.Branch
--- @field name string
--- @field reasoning string
--- @field created_at string

--- @class expedition.Breadcrumb
--- @field file string project-relative path
--- @field line number cursor line at time of visit
--- @field timestamp string ISO 8601

--- Create a new Branch object.
--- @param name string
--- @param reasoning string?
--- @return expedition.Branch
function M.new_branch(name, reasoning)
  return {
    name = name,
    reasoning = reasoning or "",
    created_at = util.timestamp(),
  }
end

--- Create a new Breadcrumb object.
--- @param file string project-relative path
--- @param line number cursor line at time of visit
--- @return expedition.Breadcrumb
function M.new_breadcrumb(file, line)
  return {
    file = file,
    line = line,
    timestamp = util.timestamp(),
  }
end

--- Create a new CampfireMessage object.
--- @param role "user"|"assistant"
--- @param content string
--- @return expedition.CampfireMessage
function M.new_campfire_message(role, content)
  return {
    role = role,
    content = content,
    timestamp = util.timestamp(),
  }
end

--- Create a new LogEntry object.
--- @param event string
--- @param expedition_id string
--- @param data table
--- @return expedition.LogEntry
function M.new_log_entry(event, expedition_id, data)
  return {
    timestamp = util.timestamp(),
    event = event,
    expedition_id = expedition_id,
    data = data or {},
  }
end

return M
