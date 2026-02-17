--- :Expedition subcommand dispatch and completion for expedition.nvim
local M = {}

--- @type table<string, fun(args: string[])>
local subcommands = {}

subcommands.create = function(args)
  if #args == 0 then
    vim.notify("[expedition] usage: :Expedition create <name>", vim.log.levels.ERROR)
    return
  end
  local name = table.concat(args, " ")
  local exp = require("expedition").create(name)
  if exp then
    vim.notify("[expedition] created expedition: " .. exp.name .. " (" .. exp.id .. ")", vim.log.levels.INFO)
  end
end

subcommands.list = function(_)
  local expedition_mod = require("expedition.expedition")
  local summaries = expedition_mod.list()
  if #summaries == 0 then
    vim.notify("[expedition] no expeditions found", vim.log.levels.INFO)
    return
  end
  local active = expedition_mod.get_active()
  local lines = { "Expeditions:" }
  for _, s in ipairs(summaries) do
    local marker = (active and active.id == s.id) and " *" or "  "
    table.insert(lines, string.format(
      "%s %s [%s] (%s) %d notes",
      marker, s.name, s.id, s.status, s.note_count
    ))
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

subcommands.load = function(args)
  if #args == 0 then
    vim.notify("[expedition] usage: :Expedition load <name-or-id>", vim.log.levels.ERROR)
    return
  end
  local target = table.concat(args, " ")
  local expedition_mod = require("expedition.expedition")

  -- Try by name first, then by ID
  local exp = expedition_mod.load_by_name(target)
  if not exp then
    exp = expedition_mod.load(target)
  end
  if exp then
    vim.notify("[expedition] loaded: " .. exp.name, vim.log.levels.INFO)
    require("expedition.ui.signs").refresh_all()
  end
end

subcommands.note = function(args)
  if #args > 0 then
    -- Create note directly with body text
    local body = table.concat(args, " ")
    require("expedition").add_note({ body = body })
  else
    -- Open floating input
    require("expedition").add_note()
  end
end

subcommands.panel = function(_)
  require("expedition").toggle_panel()
end

subcommands.log = function(args)
  local expedition_mod = require("expedition.expedition")
  local active = expedition_mod.get_active()
  if not active then
    vim.notify("[expedition] no active expedition", vim.log.levels.ERROR)
    return
  end

  local log = require("expedition.log")
  local n = tonumber(args[1]) or 20
  local entries = log.tail(active.id, n)

  if #entries == 0 then
    vim.notify("[expedition] no log entries", vim.log.levels.INFO)
    return
  end

  local lines = { "Log (last " .. #entries .. " entries):" }
  for _, entry in ipairs(entries) do
    table.insert(lines, string.format(
      "  [%s] %s", entry.timestamp, entry.event
    ))
    if entry.data and next(entry.data) then
      for k, v in pairs(entry.data) do
        table.insert(lines, string.format("    %s: %s", k, tostring(v)))
      end
    end
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

subcommands.route = function(args)
  local route = require("expedition.route")
  local sub = args[1]

  if not sub or sub == "" then
    -- Show route overview
    local waypoints = route.get_route()
    if #waypoints == 0 then
      vim.notify("[expedition] no waypoints in route", vim.log.levels.INFO)
      return
    end
    local lines = { "Route:" }
    for _, wp in ipairs(waypoints) do
      table.insert(lines, string.format(
        "  [%s] %s (%s)", wp.id, wp.title, wp.status
      ))
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    return
  end

  if sub == "add" then
    local title = table.concat(vim.list_slice(args, 2), " ")
    if title == "" then
      vim.notify("[expedition] usage: :Expedition route add <title>", vim.log.levels.ERROR)
      return
    end
    local wp = route.create_waypoint({ title = title })
    if wp then
      vim.notify("[expedition] waypoint created: " .. wp.title .. " (" .. wp.id .. ")", vim.log.levels.INFO)
    end

  elseif sub == "done" then
    local id = args[2]
    if not id then
      vim.notify("[expedition] usage: :Expedition route done <id>", vim.log.levels.ERROR)
      return
    end
    local wp = route.set_status(id, "done")
    if wp then
      vim.notify("[expedition] waypoint marked done: " .. wp.title, vim.log.levels.INFO)
    end

  elseif sub == "active" then
    local id = args[2]
    if not id then
      vim.notify("[expedition] usage: :Expedition route active <id>", vim.log.levels.ERROR)
      return
    end
    local wp = route.set_status(id, "active")
    if wp then
      vim.notify("[expedition] waypoint set active: " .. wp.title, vim.log.levels.INFO)
    end

  elseif sub == "ready" then
    local ready = route.get_ready()
    if #ready == 0 then
      vim.notify("[expedition] no ready waypoints", vim.log.levels.INFO)
      return
    end
    local lines = { "Ready waypoints:" }
    for _, wp in ipairs(ready) do
      table.insert(lines, string.format("  [%s] %s", wp.id, wp.title))
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)

  elseif sub == "dep" then
    local wp_id = args[2]
    local dep_id = args[3]
    if not wp_id or not dep_id then
      vim.notify("[expedition] usage: :Expedition route dep <id> <dep-id>", vim.log.levels.ERROR)
      return
    end
    if route.add_dependency(wp_id, dep_id) then
      vim.notify("[expedition] dependency added", vim.log.levels.INFO)
    end

  elseif sub == "link" then
    local wp_id = args[2]
    local note_id = args[3]
    if not wp_id or not note_id then
      vim.notify("[expedition] usage: :Expedition route link <wp-id> <note-id>", vim.log.levels.ERROR)
      return
    end
    if route.link_note(note_id, wp_id) then
      vim.notify("[expedition] note linked to waypoint", vim.log.levels.INFO)
    end

  elseif sub == "delete" then
    local id = args[2]
    if not id then
      vim.notify("[expedition] usage: :Expedition route delete <id>", vim.log.levels.ERROR)
      return
    end
    vim.ui.select({ "Yes", "No" }, { prompt = "Delete waypoint " .. id .. "?" }, function(choice)
      if choice == "Yes" then
        if route.delete_waypoint(id) then
          vim.notify("[expedition] waypoint deleted", vim.log.levels.INFO)
        end
      end
    end)

  elseif sub == "branch" then
    local branch_sub = args[2]
    if not branch_sub or branch_sub == "" then
      -- List branches
      local branches = route.list_branches()
      local active_b = route.active_branch()
      local lines = { "Branches:" }
      for _, name in ipairs(branches) do
        local marker = (name == active_b) and " *" or "  "
        table.insert(lines, marker .. " " .. name)
      end
      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)

    elseif branch_sub == "create" then
      local name = args[3]
      if not name then
        vim.notify("[expedition] usage: :Expedition route branch create <name> [reasoning]", vim.log.levels.ERROR)
        return
      end
      local reasoning = #args >= 4 and table.concat(vim.list_slice(args, 4), " ") or nil
      route.create_branch(name, reasoning)

    elseif branch_sub == "switch" then
      local name = args[3]
      if not name then
        vim.notify("[expedition] usage: :Expedition route branch switch <name>", vim.log.levels.ERROR)
        return
      end
      route.switch_branch(name)

    elseif branch_sub == "list" then
      local branches = route.list_branches()
      local active_b = route.active_branch()
      local lines = { "Branches:" }
      for _, name in ipairs(branches) do
        local marker = (name == active_b) and " *" or "  "
        table.insert(lines, marker .. " " .. name)
      end
      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)

    elseif branch_sub == "merge" then
      local source = args[3]
      local target = args[4]
      if not source or not target then
        vim.notify("[expedition] usage: :Expedition route branch merge <source> <target>", vim.log.levels.ERROR)
        return
      end
      route.merge_branch(source, target)

    else
      vim.notify("[expedition] unknown branch subcommand: " .. branch_sub, vim.log.levels.ERROR)
    end

  else
    vim.notify("[expedition] unknown route subcommand: " .. sub, vim.log.levels.ERROR)
  end
end

subcommands.plan = function(_)
  local provider = require("expedition.ai.provider")
  local ok, reason = provider.is_available()
  if not ok then
    vim.notify("[expedition] " .. (reason or "AI not available"), vim.log.levels.ERROR)
    return
  end

  local prompt_mod = require("expedition.ai.prompt")
  local parse = require("expedition.ai.parse")
  local propose = require("expedition.ui.propose")

  local prompt_text, system = prompt_mod.build_planning_prompt()

  vim.notify("[expedition] Generating route proposal...", vim.log.levels.INFO)

  provider.call({
    prompt = prompt_text,
    system = system,
    on_success = function(response)
      local proposal, err = parse.parse_proposal(response)
      if not proposal then
        vim.notify("[expedition] Failed to parse proposal: " .. (err or "unknown error"), vim.log.levels.ERROR)
        return
      end
      propose.open(proposal)
    end,
    on_error = function(err)
      vim.notify("[expedition] AI error: " .. err, vim.log.levels.ERROR)
    end,
  })
end

subcommands.replan = function(args)
  local provider = require("expedition.ai.provider")
  local ok, reason = provider.is_available()
  if not ok then
    vim.notify("[expedition] " .. (reason or "AI not available"), vim.log.levels.ERROR)
    return
  end

  local prompt_mod = require("expedition.ai.prompt")
  local parse = require("expedition.ai.parse")
  local propose = require("expedition.ui.propose")

  local context = #args > 0 and table.concat(args, " ") or nil
  local prompt_text, system = prompt_mod.build_replan_prompt(context)

  vim.notify("[expedition] Generating replan proposal...", vim.log.levels.INFO)

  provider.call({
    prompt = prompt_text,
    system = system,
    on_success = function(response)
      local proposal, err = parse.parse_proposal(response)
      if not proposal then
        vim.notify("[expedition] Failed to parse proposal: " .. (err or "unknown error"), vim.log.levels.ERROR)
        return
      end
      propose.open(proposal)
    end,
    on_error = function(err)
      vim.notify("[expedition] AI error: " .. err, vim.log.levels.ERROR)
    end,
  })
end

subcommands.campfire = function(_)
  local provider = require("expedition.ai.provider")
  local ok, reason = provider.is_available()
  if not ok then
    vim.notify("[expedition] " .. (reason or "AI not available"), vim.log.levels.ERROR)
    return
  end

  require("expedition.ui.campfire").toggle()
end

subcommands.summit = function(_)
  local provider = require("expedition.ai.provider")
  local ok, reason = provider.is_available()
  if not ok then
    vim.notify("[expedition] " .. (reason or "AI not available"), vim.log.levels.ERROR)
    return
  end

  local prompt_mod = require("expedition.ai.prompt")
  local parse = require("expedition.ai.parse")

  local prompt_text, system = prompt_mod.build_summit_eval_prompt()

  vim.notify("[expedition] Evaluating expedition...", vim.log.levels.INFO)

  provider.call({
    prompt = prompt_text,
    system = system,
    on_success = function(response)
      local eval, err = parse.parse_summit_eval(response)
      if not eval then
        vim.notify("[expedition] Failed to parse evaluation: " .. (err or "unknown error"), vim.log.levels.ERROR)
        return
      end

      local status = eval.ready and "READY" or "NOT READY"
      local lines = {
        "[expedition] Summit Evaluation: " .. status,
        "  Confidence: " .. string.format("%.0f%%", eval.confidence * 100),
        "  " .. eval.reasoning,
      }
      if #eval.remaining > 0 then
        table.insert(lines, "  Remaining:")
        for _, item in ipairs(eval.remaining) do
          table.insert(lines, "    - " .. item)
        end
      end
      local level = eval.ready and vim.log.levels.INFO or vim.log.levels.WARN
      vim.notify(table.concat(lines, "\n"), level)
    end,
    on_error = function(err)
      vim.notify("[expedition] AI error: " .. err, vim.log.levels.ERROR)
    end,
  })
end

subcommands.drift = function(args)
  local expedition_mod = require("expedition.expedition")
  local active = expedition_mod.get_active()
  if not active then
    vim.notify("[expedition] no active expedition", vim.log.levels.ERROR)
    return
  end

  local drift = require("expedition.drift")
  local sub = args[1]

  if sub == "check" then
    local buf = vim.api.nvim_get_current_buf()
    drift.check({ buf = buf, file = vim.api.nvim_buf_get_name(buf) })
    vim.notify("[expedition] drift check completed", vim.log.levels.INFO)

  elseif sub == "ack" then
    local note_id = args[2]
    if note_id then
      drift.acknowledge(note_id)
    else
      drift.acknowledge_buffer()
    end

  else
    -- List all drifted notes
    local note_mod = require("expedition.note")
    local notes = note_mod.list()
    local drifted = {}
    for _, n in ipairs(notes) do
      if n.drift_status == "drifted" then
        table.insert(drifted, n)
      end
    end
    if #drifted == 0 then
      vim.notify("[expedition] no drifted notes", vim.log.levels.INFO)
      return
    end
    local lines = { "Drifted notes:" }
    for _, n in ipairs(drifted) do
      local loc = ""
      if n.anchor then
        loc = n.anchor.file .. ":" .. n.anchor.line .. " - "
      end
      local body_preview = (n.body:match("^[^\n]*") or ""):sub(1, 40)
      table.insert(lines, string.format("  [%s] %s%s", n.id, loc, body_preview))
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end
end

subcommands.breadcrumbs = function(args)
  local expedition_mod = require("expedition.expedition")
  local active = expedition_mod.get_active()
  if not active then
    vim.notify("[expedition] no active expedition", vim.log.levels.ERROR)
    return
  end

  local bc = require("expedition.breadcrumbs")
  local sub = args[1]

  if sub == "promote" then
    local index = tonumber(args[2])
    if not index then
      vim.notify("[expedition] usage: :Expedition breadcrumbs promote <index>", vim.log.levels.ERROR)
      return
    end
    bc.promote(index)
  else
    local n = tonumber(sub) or 20
    local entries = bc.list(n)
    if #entries == 0 then
      vim.notify("[expedition] no breadcrumbs recorded", vim.log.levels.INFO)
      return
    end
    local lines = { "Breadcrumbs (last " .. #entries .. "):" }
    for i, entry in ipairs(entries) do
      table.insert(lines, string.format(
        "  %d. %s:%d [%s]", i, entry.file, entry.line, entry.timestamp
      ))
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end
end

subcommands.status = function(_)
  local expedition_mod = require("expedition.expedition")
  local active = expedition_mod.get_active()
  if not active then
    vim.notify("[expedition] no active expedition", vim.log.levels.INFO)
    return
  end

  local note_mod = require("expedition.note")
  local notes = note_mod.list()
  local anchored = 0
  for _, n in ipairs(notes) do
    if n.anchor then anchored = anchored + 1 end
  end

  local route = require("expedition.route")
  local waypoints = route.list()
  local wp_done = 0
  local wp_active = 0
  for _, wp in ipairs(waypoints) do
    if wp.status == "done" then wp_done = wp_done + 1 end
    if wp.status == "active" then wp_active = wp_active + 1 end
  end

  local lines = {
    "Expedition: " .. active.name,
    "  ID: " .. active.id,
    "  Status: " .. active.status,
    "  Created: " .. active.created_at,
    "  Notes: " .. #notes .. " (" .. anchored .. " anchored)",
    "  Waypoints: " .. #waypoints .. " (" .. wp_done .. " done, " .. wp_active .. " active)",
  }
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

--- Names of all subcommands (for completion).
local subcommand_names = vim.tbl_keys(subcommands)
table.sort(subcommand_names)

--- Register the :Expedition command.
function M.register()
  vim.api.nvim_create_user_command("Expedition", function(cmd)
    local args = vim.split(vim.fn.trim(cmd.args), "%s+")
    local subcmd = table.remove(args, 1)

    if not subcmd or subcmd == "" then
      vim.notify("[expedition] usage: :Expedition <" .. table.concat(subcommand_names, "|") .. ">", vim.log.levels.INFO)
      return
    end

    local handler = subcommands[subcmd]
    if not handler then
      vim.notify("[expedition] unknown subcommand: " .. subcmd, vim.log.levels.ERROR)
      return
    end

    -- Ensure setup has been called (except for 'create' which can trigger lazy setup)
    local config = require("expedition.config")
    if not config.is_applied() then
      require("expedition").setup()
    end

    handler(args)
  end, {
    nargs = "*",
    complete = function(arg_lead, cmd_line, _)
      local parts = vim.split(cmd_line, "%s+")
      -- Complete subcommand name
      if #parts <= 2 then
        return vim.tbl_filter(function(name)
          return name:find(arg_lead, 1, true) == 1
        end, subcommand_names)
      end

      -- Complete arguments for specific subcommands
      local subcmd = parts[2]
      if subcmd == "load" then
        local ok, expedition_mod = pcall(require, "expedition.expedition")
        if ok then
          local names = expedition_mod.list_names()
          return vim.tbl_filter(function(name)
            return name:find(arg_lead, 1, true) == 1
          end, names)
        end
      elseif subcmd == "drift" then
        if #parts == 3 then
          local drift_subs = { "check", "ack" }
          return vim.tbl_filter(function(name)
            return name:find(arg_lead, 1, true) == 1
          end, drift_subs)
        end
      elseif subcmd == "breadcrumbs" then
        if #parts == 3 then
          local bc_subs = { "promote" }
          return vim.tbl_filter(function(name)
            return name:find(arg_lead, 1, true) == 1
          end, bc_subs)
        end
      elseif subcmd == "route" then
        if #parts == 3 then
          -- Complete route sub-subcommand
          local route_subs = { "add", "done", "active", "ready", "dep", "link", "delete", "branch" }
          return vim.tbl_filter(function(name)
            return name:find(arg_lead, 1, true) == 1
          end, route_subs)
        elseif #parts >= 4 then
          local route_sub = parts[3]
          -- "link" second arg (parts==5) completes note IDs
          if route_sub == "link" and #parts == 5 then
            local ok_n, note_mod = pcall(require, "expedition.note")
            if ok_n then
              local notes = note_mod.list()
              local ids = {}
              for _, n in ipairs(notes) do
                table.insert(ids, n.id)
              end
              return vim.tbl_filter(function(id)
                return id:find(arg_lead, 1, true) == 1
              end, ids)
            end
          -- Complete waypoint IDs for route sub-subcommands that take them
          elseif route_sub == "done" or route_sub == "active" or route_sub == "delete"
            or route_sub == "dep" or route_sub == "link" then
            local ok_r, route_mod = pcall(require, "expedition.route")
            if ok_r then
              local wps = route_mod.list()
              local ids = {}
              for _, wp in ipairs(wps) do
                table.insert(ids, wp.id)
              end
              return vim.tbl_filter(function(id)
                return id:find(arg_lead, 1, true) == 1
              end, ids)
            end
          elseif route_sub == "branch" then
            if #parts == 4 then
              -- Complete branch sub-sub-subcommand
              local branch_subs = { "create", "switch", "list", "merge" }
              return vim.tbl_filter(function(name)
                return name:find(arg_lead, 1, true) == 1
              end, branch_subs)
            elseif #parts >= 5 then
              local branch_sub = parts[4]
              if branch_sub == "switch" or branch_sub == "merge" then
                local ok_r, route_mod = pcall(require, "expedition.route")
                if ok_r then
                  local branches = route_mod.list_branches()
                  return vim.tbl_filter(function(name)
                    return name:find(arg_lead, 1, true) == 1
                  end, branches)
                end
              end
            end
          end
        end
      end

      return {}
    end,
    desc = "Expedition commands",
  })
end

return M
