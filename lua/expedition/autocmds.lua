--- Autocommand registration for expedition.nvim
local M = {}

--- Register autocommands in the "Expedition" augroup.
function M.register()
  local group = vim.api.nvim_create_augroup("Expedition", { clear = true })

  -- Refresh signs when entering a buffer
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      local buf = ev.buf
      -- Only for normal file buffers
      if vim.bo[buf].buftype ~= "" then return end
      local name = vim.api.nvim_buf_get_name(buf)
      if name == "" then return end

      -- Check if there's an active expedition before doing work
      local config = require("expedition.config")
      if not config.is_applied() then return end

      local expedition_mod = require("expedition.expedition")
      if not expedition_mod.get_active() then return end

      vim.schedule(function()
        require("expedition.ui.signs").refresh(buf)
      end)
    end,
  })

  -- Dispatch buf_write event for drift detection (Phase 4)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(ev)
      local buf = ev.buf
      if vim.bo[buf].buftype ~= "" then return end

      local config = require("expedition.config")
      if not config.is_applied() then return end

      local hooks = require("expedition.hooks")
      hooks.dispatch("buf_write", {
        buf = buf,
        file = vim.api.nvim_buf_get_name(buf),
      })

      -- Also refresh signs after a write
      vim.schedule(function()
        local expedition_mod = require("expedition.expedition")
        if expedition_mod.get_active() then
          require("expedition.ui.signs").refresh(buf)
        end
      end)
    end,
  })
end

return M
