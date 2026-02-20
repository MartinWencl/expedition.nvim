--- State → text serializer for expedition.nvim
--- Phase 1: basic human-readable text. Phase 3 extends for AI prompt construction.
local M = {}

--- Serialize a single note to text.
--- @param note expedition.Note
--- @return string
function M.serialize_note(note)
  local parts = {}
  table.insert(parts, "## Note [" .. note.id .. "]")

  if note.anchor then
    local loc = note.anchor.file .. ":" .. note.anchor.line
    if note.anchor.symbol then
      loc = loc .. " (" .. note.anchor.symbol .. ")"
    end
    table.insert(parts, "Location: " .. loc)
  end

  if note.tags and #note.tags > 0 then
    table.insert(parts, "Tags: " .. table.concat(
      vim.tbl_map(function(t) return "#" .. t end, note.tags), " "
    ))
  end

  if note.drift_status == "drifted" then
    table.insert(parts, "Drift: DRIFTED")
  end

  table.insert(parts, "")
  table.insert(parts, note.body)
  table.insert(parts, "")

  return table.concat(parts, "\n")
end

--- Serialize an expedition header to text.
--- @param exp expedition.Expedition
--- @return string
function M.serialize_expedition(exp)
  local parts = {}
  table.insert(parts, "# Expedition: " .. exp.name)
  table.insert(parts, "Status: " .. exp.status)
  table.insert(parts, "Created: " .. exp.created_at)
  if exp.description and exp.description ~= "" then
    table.insert(parts, "")
    table.insert(parts, exp.description)
  end
  table.insert(parts, "")
  return table.concat(parts, "\n")
end

--- Serialize a single waypoint to text.
--- @param wp expedition.Waypoint
--- @return string
function M.serialize_waypoint(wp)
  local status_markers = {
    blocked   = "[BLOCKED]",
    ready     = "[READY]",
    active    = "[ACTIVE]",
    done      = "[DONE]",
    abandoned = "[ABANDONED]",
  }
  local parts = {}
  local marker = status_markers[wp.status] or ("[" .. wp.status:upper() .. "]")
  table.insert(parts, "### " .. marker .. " " .. wp.title .. " [" .. wp.id .. "]")

  if wp.description ~= "" then
    table.insert(parts, wp.description)
  end
  if wp.reasoning ~= "" then
    table.insert(parts, "Reasoning: " .. wp.reasoning)
  end
  if #wp.depends_on > 0 then
    table.insert(parts, "Depends on: " .. table.concat(wp.depends_on, ", "))
  end
  if #wp.linked_note_ids > 0 then
    table.insert(parts, "Linked notes: " .. table.concat(wp.linked_note_ids, ", "))
  end
  table.insert(parts, "")

  return table.concat(parts, "\n")
end

--- Serialize a single summit condition to text.
--- @param condition expedition.SummitCondition
--- @return string
function M.serialize_condition(condition)
  local markers = { open = "[ ]", met = "[x]", abandoned = "[~]" }
  local marker = markers[condition.status] or "[ ]"
  return marker .. " " .. condition.text .. " [" .. condition.id .. "]"
end

--- Serialize all summit conditions to text.
--- @param conditions expedition.SummitCondition[]
--- @return string
function M.serialize_conditions(conditions)
  if #conditions == 0 then
    return ""
  end
  local parts = { "## Summit Conditions", "" }
  for _, c in ipairs(conditions) do
    table.insert(parts, "- " .. M.serialize_condition(c))
  end
  table.insert(parts, "")
  return table.concat(parts, "\n")
end

--- Serialize the full route (all waypoints) to text.
--- @param waypoints expedition.Waypoint[]
--- @return string
function M.serialize_route(waypoints)
  if #waypoints == 0 then
    return "## Route\n\nNo waypoints.\n"
  end
  local parts = { "## Route", "" }
  for _, wp in ipairs(waypoints) do
    table.insert(parts, M.serialize_waypoint(wp))
  end
  return table.concat(parts, "\n")
end

--- Serialize the full active expedition state to text.
--- @param opts table? { include_log? }
--- @return string
function M.serialize(opts)
  opts = opts or {}

  local expedition_mod = require("expedition.expedition")
  local note_mod = require("expedition.note")

  local active = expedition_mod.get_active()
  if not active then
    return "No active expedition.\n"
  end

  local parts = {}
  table.insert(parts, M.serialize_expedition(active))

  -- Summit conditions section (between header and notes so AI sees goals first)
  local summit = require("expedition.summit")
  local conditions = summit.list()
  local cond_text = M.serialize_conditions(conditions)
  if cond_text ~= "" then
    table.insert(parts, cond_text)
  end

  local notes = note_mod.list()
  if #notes > 0 then
    table.insert(parts, "---")
    table.insert(parts, "")
    for _, note in ipairs(notes) do
      table.insert(parts, M.serialize_note(note))
    end
  else
    table.insert(parts, "No notes yet.")
  end

  -- Route section
  local route = require("expedition.route")
  local waypoints = route.get_route()
  table.insert(parts, "---")
  table.insert(parts, "")
  table.insert(parts, M.serialize_route(waypoints))

  if opts.include_log then
    local log = require("expedition.log")
    local entries = log.read(active.id)
    if #entries > 0 then
      table.insert(parts, "---")
      table.insert(parts, "## Log")
      table.insert(parts, "")
      for _, entry in ipairs(entries) do
        table.insert(parts, string.format(
          "- [%s] %s", entry.timestamp, entry.event
        ))
      end
      table.insert(parts, "")
    end
  end

  return table.concat(parts, "\n")
end

return M
