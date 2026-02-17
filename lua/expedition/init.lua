--- expedition.nvim — Public API and setup()
--- Manages code exploration sessions with field notes attached to code locations.
local M = {}

local _ready = false

--- Check if the plugin has been set up.
--- @return boolean
function M.is_ready()
  return _ready
end

--- Assert that setup has been called.
local function assert_ready()
  if not _ready then
    error("expedition: setup() has not been called. Call require('expedition').setup() first.")
  end
end

--- Set up expedition.nvim with user options.
--- @param opts table?
function M.setup(opts)
  if _ready then return end

  local config = require("expedition.config")
  config.apply(opts)

  -- Define highlight groups
  require("expedition.ui.highlights").setup()

  -- Register autocommands
  require("expedition.autocmds").register()

  -- Register Phase 4 modules
  require("expedition.drift").register()
  require("expedition.presets").register()
  require("expedition.breadcrumbs").register()

  -- Dispatch setup hook
  require("expedition.hooks").dispatch("setup", { config = config.get() })

  _ready = true
end

--- Create a new expedition.
--- @param name string
--- @param opts table?
--- @return expedition.Expedition
function M.create(name, opts)
  assert_ready()
  return require("expedition.expedition").create(name, opts)
end

--- List all expeditions for the current project.
--- @return expedition.ExpeditionSummary[]
function M.list()
  assert_ready()
  return require("expedition.expedition").list()
end

--- Load an expedition by ID.
--- @param id string
--- @return expedition.Expedition?
function M.load(id)
  assert_ready()
  return require("expedition.expedition").load(id)
end

--- Get the currently active expedition.
--- @return expedition.Expedition?
function M.get_active()
  assert_ready()
  return require("expedition.expedition").get_active()
end

--- Add a note to the active expedition.
--- If opts.body is given, creates directly. Otherwise opens floating input.
--- @param opts table? { body?, tags?, anchor?, visual? }
function M.add_note(opts)
  assert_ready()
  opts = opts or {}

  if opts.body then
    local note_mod = require("expedition.note")
    -- Auto-extract tags from body if not explicitly provided
    local tags = opts.tags
    if not tags then
      tags = {}
      local seen = {}
      for tag in opts.body:gmatch("#(%w+)") do
        if not seen[tag] then
          table.insert(tags, tag)
          seen[tag] = true
        end
      end
    end
    local create_opts = { tags = tags, anchor = opts.anchor, meta = opts.meta }

    -- If no anchor provided but we're in a file buffer, capture one
    if not opts.anchor then
      local buf = vim.api.nvim_get_current_buf()
      if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
        create_opts.anchor = require("expedition.anchor").from_cursor(buf)
      end
    end

    local note = note_mod.create(opts.body, create_opts)
    if note then
      vim.notify("[expedition] note created", vim.log.levels.INFO)
      require("expedition.ui.signs").refresh_all()
    end
    return
  end

  -- Open floating input
  local mode = vim.fn.mode()
  local visual = mode == "v" or mode == "V" or mode == "\22" -- \22 = <C-v>
  -- Exit visual mode first so marks are set
  if visual then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  end
  vim.schedule(function()
    require("expedition.ui.input").open({ visual = visual })
  end)
end

--- Delete a note by ID.
--- @param id string
--- @return boolean
function M.delete_note(id)
  assert_ready()
  local result = require("expedition.note").delete(id)
  if result then
    require("expedition.ui.signs").refresh_all()
  end
  return result
end

--- Toggle the side panel.
function M.toggle_panel()
  assert_ready()
  require("expedition.ui.panel").toggle()
end

--- Refresh signs in all visible buffers.
function M.refresh_signs()
  assert_ready()
  require("expedition.ui.signs").refresh_all()
end

--- Add a waypoint to the active expedition's route.
--- @param opts table { title: string, description?, depends_on?, reasoning?, branch? }
--- @return expedition.Waypoint?
function M.add_waypoint(opts)
  assert_ready()
  return require("expedition.route").create_waypoint(opts)
end

--- Get the route (topo-sorted waypoints) for the active expedition.
--- @param branch string?
--- @return expedition.Waypoint[]
function M.get_route(branch)
  assert_ready()
  return require("expedition.route").get_route(branch)
end

--- Set a waypoint's status.
--- @param id string
--- @param status string
--- @return expedition.Waypoint?
function M.set_waypoint_status(id, status)
  assert_ready()
  return require("expedition.route").set_status(id, status)
end

--- Link a note to a waypoint (bidirectional).
--- @param note_id string
--- @param wp_id string
--- @return boolean
function M.link_note_to_waypoint(note_id, wp_id)
  assert_ready()
  return require("expedition.route").link_note(note_id, wp_id)
end

--- Run AI route planning.
function M.plan()
  vim.cmd("Expedition plan")
end

--- Toggle campfire brainstorm chat.
function M.campfire()
  vim.cmd("Expedition campfire")
end

--- Run summit evaluation.
function M.summit()
  vim.cmd("Expedition summit")
end

return M
