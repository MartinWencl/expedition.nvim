--- Data model constructors and LuaCATS annotations for expedition.nvim
local util = require("expedition.util")

local M = {}

--- @alias expedition.ExpeditionId string 8-char hex expedition identifier
--- @alias expedition.WaypointId string 8-char hex waypoint identifier
--- @alias expedition.NoteId string 8-char hex note identifier
--- @alias expedition.ConditionId string 8-char hex condition identifier
--- @alias expedition.Timestamp string ISO 8601 (e.g. "2025-01-01T00:00:00Z")
--- @alias expedition.ProjectId string FNV-1a hash of project root path

--- @class expedition.Expedition
--- @field id expedition.ExpeditionId
--- @field name string
--- @field description string
--- @field created_at expedition.Timestamp ISO 8601
--- @field updated_at expedition.Timestamp
--- @field status "active"|"paused"|"completed"|"archived"
--- @field meta table freeform extension point

--- @class expedition.ExpeditionSummary
--- @field id expedition.ExpeditionId
--- @field name string
--- @field status "active"|"paused"|"completed"|"archived"
--- @field created_at expedition.Timestamp
--- @field note_count number

--- @class expedition.Note
--- @field id expedition.NoteId
--- @field expedition_id expedition.ExpeditionId
--- @field body string
--- @field tags string[]
--- @field anchor expedition.Anchor?
--- @field created_at expedition.Timestamp
--- @field updated_at expedition.Timestamp
--- @field drift_status "ok"|"drifted"?
--- @field meta table Phase 2: { waypoint_id = "..." }

--- @class expedition.Anchor
--- @field file string project-relative path
--- @field line number 1-indexed
--- @field end_line number? for visual selection ranges
--- @field symbol string? e.g. "function:parse_config"
--- @field snapshot_hash string
--- @field snapshot_lines string[]

--- @class expedition.Waypoint
--- @field id expedition.WaypointId
--- @field title string
--- @field description string
--- @field status "blocked"|"ready"|"active"|"done"|"abandoned"
--- @field depends_on expedition.WaypointId[] waypoint IDs
--- @field reasoning string
--- @field linked_note_ids expedition.NoteId[]
--- @field branch string
--- @field created_at expedition.Timestamp
--- @field updated_at expedition.Timestamp

--- @class expedition.SummitCondition
--- @field id expedition.ConditionId
--- @field text string
--- @field status "open"|"met"|"abandoned"
--- @field created_at expedition.Timestamp
--- @field updated_at expedition.Timestamp

--- @class expedition.LogEntry
--- @field timestamp expedition.Timestamp
--- @field event string e.g. "expedition.created", "note.created"
--- @field expedition_id expedition.ExpeditionId
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
--- @param expedition_id expedition.ExpeditionId
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

--- Create a new SummitCondition object.
--- @param text string
--- @param opts table?
--- @return expedition.SummitCondition
function M.new_summit_condition(text, opts)
  opts = opts or {}
  local now = util.timestamp()
  return {
    id = util.id(),
    text = text,
    status = opts.status or "open",
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
--- @field timestamp expedition.Timestamp

--- @class expedition.SummitEvaluation
--- @field ready boolean
--- @field confidence number
--- @field reasoning string
--- @field remaining string[]
--- @field conditions expedition.ConditionAssessment[]?

--- @class expedition.ConditionAssessment
--- @field id expedition.ConditionId
--- @field assessment "met"|"not_met"|"abandoned"
--- @field reasoning string

--- @class expedition.Branch
--- @field name string
--- @field reasoning string
--- @field created_at expedition.Timestamp

--- @class expedition.Breadcrumb
--- @field file string project-relative path
--- @field line number cursor line at time of visit
--- @field timestamp expedition.Timestamp ISO 8601

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
--- @param expedition_id expedition.ExpeditionId
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
