--- Test bootstrap for expedition.nvim busted specs
--- Runs before each spec file via .busted config.

-- Capture vim.notify calls instead of printing them
_G._test_notifications = {}
vim.notify = function(msg, level, opts)
  table.insert(_G._test_notifications, { msg = msg, level = level, opts = opts })
end

-- Create a temp directory for test data isolation
local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

-- Initialize config pointing at the temp directory
require("expedition.config").apply({ data_dir = tmpdir })

--- Create a fresh expedition and set it as active.
--- @param name string?
--- @return expedition.Expedition
function _G.test_create_expedition(name)
  local expedition_mod = require("expedition.expedition")
  return expedition_mod.create(name or "test-expedition")
end

--- Reset test state between tests.
function _G.test_reset()
  require("expedition.hooks").clear()
  _G._test_notifications = {}
end

function _G.test_clear_active()
  require("expedition.expedition")._reset()
end

function _G.test_reset_route()
  require("expedition.route")._reset()
end
