--- Thin UI dispatcher for expedition.nvim
local M = {}

function M.toggle_panel()
  require("expedition.ui.panel").toggle()
end

function M.open_panel()
  require("expedition.ui.panel").open()
end

function M.close_panel()
  require("expedition.ui.panel").close()
end

function M.open_input(opts)
  require("expedition.ui.input").open(opts)
end

function M.refresh_signs(buf)
  require("expedition.ui.signs").refresh(buf)
end

function M.refresh_all_signs()
  require("expedition.ui.signs").refresh_all()
end

function M.setup_highlights()
  require("expedition.ui.highlights").setup()
end

function M.find_notes(opts)
  require("expedition.ui.picker").notes(opts)
end

function M.find_waypoints(opts)
  require("expedition.ui.picker").waypoints(opts)
end

function M.find_expeditions(opts)
  require("expedition.ui.picker").expeditions(opts)
end

function M.find_conditions(opts)
  require("expedition.ui.picker").conditions(opts)
end

function M.find_breadcrumbs(opts)
  require("expedition.ui.picker").breadcrumbs(opts)
end

function M.ticker_render()
  require("expedition.ui.ticker").render()
end

function M.ticker_hide()
  require("expedition.ui.ticker").hide()
end

return M
