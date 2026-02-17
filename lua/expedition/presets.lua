--- Hook preset recipes for expedition.nvim
--- Shipped AI-powered hook recipes that can be enabled via config.
local hooks = require("expedition.hooks")
local config = require("expedition.config")

local M = {}

--- @type function[] unregister handles for active presets
local _active = {}

--- Clear all active preset hooks.
function M.clear()
  for _, unregister in ipairs(_active) do
    unregister()
  end
  _active = {}
end

--- Register enabled presets based on config.
function M.register()
  M.clear()

  local presets = config.val("hooks.presets")
  if not presets then return end

  if presets.ai_conflict_check then
    M._register_ai_conflict_check()
  end
  if presets.ai_drift_review then
    M._register_ai_drift_review()
  end
  if presets.auto_summit_eval then
    M._register_auto_summit_eval()
  end
end

--- ai_conflict_check: On note.created, check for conflicts with active/ready waypoints.
function M._register_ai_conflict_check()
  local unreg = hooks.on("note.created", function(payload)
    local provider = require("expedition.ai.provider")
    local ok = provider.is_available()
    if not ok then return end

    local route = require("expedition.route")
    local waypoints = route.get_route()
    local active_wps = {}
    for _, wp in ipairs(waypoints) do
      if wp.status == "active" or wp.status == "ready" then
        table.insert(active_wps, wp)
      end
    end
    if #active_wps == 0 then return end

    local note = payload.note
    local wp_list = {}
    for _, wp in ipairs(active_wps) do
      table.insert(wp_list, string.format("- %s (%s): %s", wp.title, wp.status, wp.description))
    end

    local prompt = string.format(
      "A new field note was created:\n\n%s\n\nActive/ready waypoints:\n%s\n\n"
        .. "Does this note conflict with or contradict any of these waypoints? "
        .. "If yes, explain the conflict briefly. If no conflict, respond with just 'No conflict.'",
      note.body,
      table.concat(wp_list, "\n")
    )

    provider.call({
      prompt = prompt,
      on_success = function(response)
        local lower = response:lower()
        if not lower:find("no conflict") then
          vim.schedule(function()
            vim.notify("[expedition] Potential conflict detected:\n" .. response, vim.log.levels.WARN)
          end)
        end
      end,
      on_error = function(_) end,
    })
  end)
  table.insert(_active, unreg)
end

--- ai_drift_review: On note.drift_detected, assess impact of code changes.
function M._register_ai_drift_review()
  local unreg = hooks.on("note.drift_detected", function(payload)
    local provider = require("expedition.ai.provider")
    local ok = provider.is_available()
    if not ok then return end

    local note = payload.note
    local anchor_info = ""
    if note.anchor then
      anchor_info = string.format("File: %s, Line: %d", note.anchor.file, note.anchor.line)
      if note.anchor.snapshot_lines and #note.anchor.snapshot_lines > 0 then
        anchor_info = anchor_info .. "\nOriginal code:\n" .. table.concat(note.anchor.snapshot_lines, "\n")
      end
    end

    local prompt = string.format(
      "A code drift was detected for a field note.\n\n"
        .. "Note: %s\n%s\n"
        .. "Old hash: %s\nNew hash: %s\n\n"
        .. "Briefly assess the potential impact of this code change on the note's relevance. "
        .. "Is the note still valid, or does it need updating?",
      note.body,
      anchor_info,
      payload.old_hash or "unknown",
      payload.new_hash or "unknown"
    )

    provider.call({
      prompt = prompt,
      on_success = function(response)
        vim.schedule(function()
          vim.notify("[expedition] Drift impact assessment:\n" .. response, vim.log.levels.INFO)
        end)
      end,
      on_error = function(_) end,
    })
  end)
  table.insert(_active, unreg)
end

--- auto_summit_eval: On waypoint.status_changed to done, trigger summit if all done.
function M._register_auto_summit_eval()
  local unreg = hooks.on("waypoint.status_changed", function(payload)
    if payload.to ~= "done" then return end

    local route = require("expedition.route")
    local waypoints = route.list()
    for _, wp in ipairs(waypoints) do
      if wp.status ~= "done" and wp.status ~= "abandoned" then
        return
      end
    end

    vim.schedule(function()
      vim.cmd("Expedition summit")
    end)
  end)
  table.insert(_active, unreg)
end

return M
