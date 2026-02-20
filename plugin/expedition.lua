-- Guard against double-load
if vim.g.loaded_expedition then return end
vim.g.loaded_expedition = true

-- Register commands (lazy-requires inside callbacks)
require("expedition.commands").register()

-- Define <Plug> mappings
vim.keymap.set({ "n", "x" }, "<Plug>(ExpeditionAddNote)", function()
  require("expedition").add_note()
end, { desc = "Add expedition note" })

vim.keymap.set("n", "<Plug>(ExpeditionTogglePanel)", function()
  require("expedition").toggle_panel()
end, { desc = "Toggle expedition panel" })

vim.keymap.set("n", "<Plug>(ExpeditionNextNote)", function()
  require("expedition.ui.signs").jump_next()
end, { desc = "Jump to next note" })

vim.keymap.set("n", "<Plug>(ExpeditionPrevNote)", function()
  require("expedition.ui.signs").jump_prev()
end, { desc = "Jump to previous note" })

vim.keymap.set("n", "<Plug>(ExpeditionAddWaypoint)", function()
  vim.ui.input({ prompt = "Waypoint title: " }, function(title)
    if title and title ~= "" then
      require("expedition").add_waypoint({ title = title })
    end
  end)
end, { desc = "Add expedition waypoint" })

vim.keymap.set("n", "<Plug>(ExpeditionPlan)", function()
  require("expedition").plan()
end, { desc = "AI route planning" })

vim.keymap.set("n", "<Plug>(ExpeditionCampfire)", function()
  require("expedition").campfire()
end, { desc = "Toggle campfire brainstorm" })

vim.keymap.set("n", "<Plug>(ExpeditionSummit)", function()
  require("expedition").summit()
end, { desc = "AI summit evaluation" })

vim.keymap.set("n", "<Plug>(ExpeditionFindNotes)", function()
  require("expedition.ui.picker").notes()
end, { desc = "Find expedition notes" })

vim.keymap.set("n", "<Plug>(ExpeditionFindWaypoints)", function()
  require("expedition.ui.picker").waypoints()
end, { desc = "Find expedition waypoints" })

vim.keymap.set("n", "<Plug>(ExpeditionFindExpeditions)", function()
  require("expedition.ui.picker").expeditions()
end, { desc = "Find expeditions" })

vim.keymap.set("n", "<Plug>(ExpeditionFindConditions)", function()
  require("expedition.ui.picker").conditions()
end, { desc = "Find summit conditions" })

vim.keymap.set("n", "<Plug>(ExpeditionFindBreadcrumbs)", function()
  require("expedition.ui.picker").breadcrumbs()
end, { desc = "Find breadcrumbs" })

vim.keymap.set("n", "<Plug>(ExpeditionAddGoal)", function()
  vim.ui.input({ prompt = "Summit condition: " }, function(text)
    if text and text ~= "" then
      require("expedition").add_summit_condition(text)
    end
  end)
end, { desc = "Add summit condition" })
