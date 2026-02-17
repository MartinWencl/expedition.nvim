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

return M
