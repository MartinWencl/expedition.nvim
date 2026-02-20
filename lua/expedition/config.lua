--- Configuration management for expedition.nvim
local M = {}

--- @class expedition.SignsConfig
--- @field enabled boolean
--- @field icon string
--- @field priority number

--- @class expedition.PanelConfig
--- @field position "left"|"right"
--- @field width number

--- @class expedition.InputConfig
--- @field width number
--- @field height number
--- @field border string

--- @class expedition.AnchorConfig
--- @field use_treesitter boolean
--- @field snapshot_context number

--- @class expedition.KeymapConfig
--- @field add_note string
--- @field toggle_panel string
--- @field next_note string
--- @field prev_note string
--- @field find_notes string

--- @class expedition.LogConfig
--- @field enabled boolean

--- @class expedition.RouteConfig
--- @field default_branch string

--- @class expedition.AiConfig
--- @field enabled boolean
--- @field backend "cli"
--- @field cli expedition.AiCliConfig
--- @field prompts expedition.AiPromptConfig

--- @class expedition.AiCliConfig
--- @field cmd string
--- @field args string[]
--- @field timeout number

--- @class expedition.AiPromptConfig
--- @field system string?

--- @class expedition.HooksPresetsConfig
--- @field ai_conflict_check boolean
--- @field ai_drift_review boolean
--- @field auto_summit_eval boolean

--- @class expedition.BreadcrumbsConfig
--- @field enabled boolean
--- @field max_entries number

--- @class expedition.StatuslineConfig
--- @field enabled boolean

--- @class expedition.TickerShowConfig
--- @field active_waypoint boolean
--- @field progress boolean
--- @field next_up number
--- @field events boolean

--- @class expedition.TickerConfig
--- @field enabled boolean
--- @field show expedition.TickerShowConfig
--- @field event_timeout number

--- @class expedition.Config
--- @field data_dir string
--- @field signs expedition.SignsConfig
--- @field panel expedition.PanelConfig
--- @field input expedition.InputConfig
--- @field anchor expedition.AnchorConfig
--- @field keymaps expedition.KeymapConfig
--- @field log expedition.LogConfig
--- @field route expedition.RouteConfig
--- @field ai expedition.AiConfig
--- @field hooks table
--- @field breadcrumbs expedition.BreadcrumbsConfig
--- @field statusline expedition.StatuslineConfig
--- @field ticker expedition.TickerConfig

--- @type expedition.Config
local defaults = {
  data_dir = vim.fn.stdpath("data") .. "/expedition",
  signs = { enabled = true, icon = "▐", priority = 10 },
  panel = { position = "right", width = 40 },
  input = { width = 60, height = 10, border = "rounded" },
  anchor = { use_treesitter = true, snapshot_context = 3 },
  keymaps = {
    add_note = "<leader>en",
    toggle_panel = "<leader>ep",
    next_note = "]n",
    prev_note = "[n",
    find_notes = "<leader>ef",
  },
  log = { enabled = true },
  route = { default_branch = "main" },
  ai = {
    enabled = false,
    backend = "cli",
    cli = {
      cmd = "claude",
      args = { "-p", "--no-session-persistence" },
      timeout = 120000,
    },
    prompts = {
      system = nil,
    },
  },
  hooks = {
    presets = {
      ai_conflict_check = false,
      ai_drift_review = false,
      auto_summit_eval = false,
    },
  },
  breadcrumbs = {
    enabled = false,
    max_entries = 1000,
  },
  statusline = {
    enabled = true,
  },
  ticker = {
    enabled = false,
    show = {
      active_waypoint = true,
      progress = true,
      next_up = 2,
      events = true,
    },
    event_timeout = 4000,
  },
}

--- @type expedition.Config?
local _config = nil

--- Apply user options on top of defaults.
--- @param opts table?
function M.apply(opts)
  _config = vim.tbl_deep_extend("force", defaults, opts or {})

  -- Set up default keymaps using hasmapto check
  local cfg = _config
  local maps = {
    { mode = { "n", "x" }, lhs = cfg.keymaps.add_note, plug = "<Plug>(ExpeditionAddNote)" },
    { mode = { "n" }, lhs = cfg.keymaps.toggle_panel, plug = "<Plug>(ExpeditionTogglePanel)" },
    { mode = { "n" }, lhs = cfg.keymaps.next_note, plug = "<Plug>(ExpeditionNextNote)" },
    { mode = { "n" }, lhs = cfg.keymaps.prev_note, plug = "<Plug>(ExpeditionPrevNote)" },
    { mode = { "n" }, lhs = cfg.keymaps.find_notes, plug = "<Plug>(ExpeditionFindNotes)" },
  }
  for _, m in ipairs(maps) do
    if vim.fn.hasmapto(m.plug) == 0 then
      vim.keymap.set(m.mode, m.lhs, m.plug, { remap = true })
    end
  end
end

--- Get the current config. Errors if setup() hasn't been called.
--- @return expedition.Config
function M.get()
  if not _config then
    error("expedition: setup() has not been called")
  end
  return _config
end

--- Get a nested config value by dot-separated path.
--- @param dotpath string e.g. "panel.width"
--- @return any
function M.val(dotpath)
  local cfg = M.get()
  local value = cfg
  for key in dotpath:gmatch("[^.]+") do
    if type(value) ~= "table" then return nil end
    value = value[key]
  end
  return value
end

--- Check if config has been applied.
--- @return boolean
function M.is_applied()
  return _config ~= nil
end

return M
