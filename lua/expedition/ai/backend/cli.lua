--- Claude CLI backend for expedition.nvim AI features
--- Calls `claude -p` via vim.system() with prompt on stdin.
local M = {}

--- Check if the CLI is available.
--- @return boolean, string?
function M.is_available()
  local config = require("expedition.config")
  local cmd = config.val("ai.cli.cmd")
  if vim.fn.executable(cmd) == 1 then
    return true
  end
  return false, "CLI not found: " .. cmd .. " (install Claude Code CLI)"
end

--- Call the Claude CLI with a request.
--- @param request expedition.AiRequest
--- @return expedition.AiHandle?
function M.call(request)
  local config = require("expedition.config")
  local cli = config.val("ai.cli")

  local cmd = { cli.cmd }
  for _, arg in ipairs(cli.args) do
    table.insert(cmd, arg)
  end

  -- Add system prompt if provided
  if request.system then
    table.insert(cmd, "--system-prompt")
    table.insert(cmd, request.system)
  end

  local obj = vim.system(cmd, {
    stdin = request.prompt,
    timeout = cli.timeout,
  }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        local output = result.stdout or ""
        request.on_success(output)
      else
        local err = result.stderr or ""
        if err == "" then
          err = "CLI exited with code " .. tostring(result.code)
        end
        request.on_error(err)
      end
    end)
  end)

  return {
    cancel = function()
      obj:kill("sigterm")
    end,
  }
end

return M
