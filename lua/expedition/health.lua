--- Health check for expedition.nvim (:checkhealth expedition)
local M = {}

function M.check()
  vim.health.start("expedition.nvim")

  -- Check Neovim version
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.error("Neovim >= 0.10 required", { "Upgrade Neovim to 0.10 or later" })
  end

  -- Check if setup has been called
  local config = require("expedition.config")
  if config.is_applied() then
    vim.health.ok("setup() has been called")
  else
    vim.health.warn("setup() has not been called", { "Add require('expedition').setup() to your config" })
  end

  -- Check data directory writable
  if config.is_applied() then
    local data_dir = config.get().data_dir
    vim.fn.mkdir(data_dir, "p")
    local test_file = data_dir .. "/.health_check"
    local f = io.open(test_file, "w")
    if f then
      f:write("ok")
      f:close()
      os.remove(test_file)
      vim.health.ok("Data directory writable: " .. data_dir)
    else
      vim.health.error("Data directory not writable: " .. data_dir)
    end
  end

  -- Check treesitter
  if vim.treesitter and vim.treesitter.get_node then
    vim.health.ok("Treesitter available")
  else
    vim.health.warn("Treesitter not available", { "Treesitter is optional but enables symbol anchoring" })
  end

  -- Check JSON encode/decode
  local ok, _ = pcall(function()
    local encoded = vim.json.encode({ test = true })
    local decoded = vim.json.decode(encoded)
    assert(decoded.test == true)
  end)
  if ok then
    vim.health.ok("JSON encode/decode works")
  else
    vim.health.error("JSON encode/decode failed")
  end

  -- Check active expedition loadable
  if config.is_applied() then
    local expedition_mod = require("expedition.expedition")
    local active = expedition_mod.get_active()
    if active then
      vim.health.ok("Active expedition: " .. active.name .. " (" .. active.id .. ")")

      -- Route integrity check
      local route = require("expedition.route")
      local waypoints = route.list()
      vim.health.ok("Waypoints: " .. #waypoints)

      -- Check for orphaned dependency references
      local wp_ids = {}
      for _, wp in ipairs(waypoints) do
        wp_ids[wp.id] = true
      end
      local orphaned = {}
      for _, wp in ipairs(waypoints) do
        for _, dep_id in ipairs(wp.depends_on) do
          if not wp_ids[dep_id] then
            table.insert(orphaned, wp.id .. " → " .. dep_id)
          end
        end
      end
      if #orphaned > 0 then
        vim.health.warn(
          "Orphaned dependency references: " .. table.concat(orphaned, ", "),
          { "These waypoints reference deleted dependencies" }
        )
      else
        vim.health.ok("No orphaned dependency references")
      end
    else
      vim.health.info("No active expedition")
    end
  end

  -- AI health checks
  vim.health.start("expedition.nvim AI")
  if config.is_applied() and config.val("ai.enabled") then
    local backend = config.val("ai.backend")
    vim.health.ok("AI enabled, backend: " .. backend)

    if backend == "cli" then
      local cmd = config.val("ai.cli.cmd")
      if vim.fn.executable(cmd) == 1 then
        vim.health.ok("CLI found: " .. cmd)
      else
        vim.health.error("CLI not found: " .. cmd, {
          "Install Claude Code CLI: npm install -g @anthropic-ai/claude-code",
        })
      end
    end
  else
    vim.health.info("AI features disabled (set ai = { enabled = true } in setup())")
  end
end

return M
