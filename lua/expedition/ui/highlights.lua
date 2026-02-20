--- Highlight group definitions for expedition.nvim
--- Uses `default = true` so user overrides survive.
local M = {}

--- Define all highlight groups.
function M.setup()
  local groups = {
    { "ExpeditionNote", { default = true, link = "DiagnosticInfo" } },
    { "ExpeditionNoteDrifted", { default = true, link = "DiagnosticWarn" } },
    { "ExpeditionPanelTitle", { default = true, link = "Title" } },
    { "ExpeditionPanelFile", { default = true, link = "Directory" } },
    { "ExpeditionPanelNote", { default = true, link = "Normal" } },
    { "ExpeditionPanelNoteId", { default = true, link = "Comment" } },
    { "ExpeditionInputBorder", { default = true, link = "FloatBorder" } },
    { "ExpeditionWaypointBlocked", { default = true, link = "DiagnosticError" } },
    { "ExpeditionWaypointReady", { default = true, link = "DiagnosticHint" } },
    { "ExpeditionWaypointActive", { default = true, link = "DiagnosticWarn" } },
    { "ExpeditionWaypointDone", { default = true, link = "DiagnosticOk" } },
    { "ExpeditionWaypointAbandoned", { default = true, link = "Comment" } },
    { "ExpeditionProposalAccepted", { default = true, link = "DiagnosticOk" } },
    { "ExpeditionProposalRejected", { default = true, link = "DiagnosticError" } },
    { "ExpeditionProposalPending", { default = true, link = "DiagnosticHint" } },
    { "ExpeditionCampfireUser", { default = true, link = "Statement" } },
    { "ExpeditionCampfireThinking", { default = true, link = "Comment" } },
    { "ExpeditionTicker", { default = true, link = "Normal" } },
  }
  for _, g in ipairs(groups) do
    vim.api.nvim_set_hl(0, g[1], g[2])
  end
end

return M
