--- Coverage-aware test bootstrap.
--- Loads the regular spec helper, then registers a busted exit
--- handler to flush luacov stats (nlua does not fire __gc on exit).

dofile("spec/spec_helper.lua")

local busted = require("busted")
busted.subscribe({ "exit" }, function()
  local ok, runner = pcall(require, "luacov.runner")
  if ok and runner.initialized then
    runner.shutdown()
  end
end)
