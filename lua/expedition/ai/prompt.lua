--- Prompt construction for expedition.nvim AI features
--- Uses serializer output as the base context for all prompts.
local M = {}

local DEFAULT_SYSTEM = [[You are an AI assistant helping with code exploration and planning.
You are part of expedition.nvim, a Neovim plugin for structured code exploration sessions.
An "expedition" is a focused exploration session with field notes anchored to code locations and a waypoint route (a DAG of tasks).
Help the user plan their exploration route, brainstorm ideas, and evaluate progress.]]

--- Get the system prompt (user override or default).
--- @return string
function M.system_prompt()
  local config = require("expedition.config")
  local custom = config.val("ai.prompts.system")
  if custom and custom ~= "" then
    return custom
  end
  return DEFAULT_SYSTEM
end

--- Build the planning prompt: propose waypoints from notes.
--- @return string prompt, string system
function M.build_planning_prompt()
  local serializer = require("expedition.serializer")
  local context = serializer.serialize()

  local prompt = context .. [[

---

Based on the expedition notes and current state above, propose a route of waypoints (tasks) to explore.

Respond with JSON in this exact format:
```json
{
  "summary": "Brief summary of the proposed route",
  "waypoints": [
    {
      "title": "Short descriptive title",
      "description": "What to investigate or do",
      "reasoning": "Why this waypoint is needed based on the notes",
      "depends_on_titles": ["Title of dependency waypoint"]
    }
  ]
}
```

Rules:
- Each waypoint should be a concrete, actionable step
- Use depends_on_titles to reference other proposed waypoints by their exact title
- Order from foundational tasks to higher-level ones
- Keep titles concise (under 60 chars)
- Base your proposals on the field notes and their code locations
- Do NOT propose waypoints that duplicate existing ones in the route]]

  return prompt, M.system_prompt()
end

--- Build the replan prompt: update the route based on current state.
--- @param context string? additional context from user
--- @return string prompt, string system
function M.build_replan_prompt(context)
  local serializer = require("expedition.serializer")
  local state = serializer.serialize({ include_log = true })

  local prompt = state .. [[

---

Based on the current expedition state and activity log above, propose updated waypoints for the route.
Consider what has been completed, what is in progress, and what the notes suggest.]]

  if context and context ~= "" then
    prompt = prompt .. "\n\nAdditional context from the user:\n" .. context
  end

  prompt = prompt .. [[


Respond with JSON in this exact format:
```json
{
  "summary": "Brief summary of proposed changes to the route",
  "waypoints": [
    {
      "title": "Short descriptive title",
      "description": "What to investigate or do",
      "reasoning": "Why this waypoint is needed",
      "depends_on_titles": ["Title of dependency waypoint"]
    }
  ]
}
```

Rules:
- Only propose NEW waypoints (do not duplicate existing ones)
- Reference existing waypoints by title in depends_on_titles if needed
- Consider the log to understand recent activity
- Focus on what should come next given the current progress]]

  return prompt, M.system_prompt()
end

--- Build the campfire (brainstorm) prompt.
--- @param conversation expedition.CampfireMessage[]
--- @return string prompt, string system
function M.build_campfire_prompt(conversation)
  local serializer = require("expedition.serializer")
  local context = serializer.serialize()

  local parts = { context, "\n---\n" }
  table.insert(parts, "Conversation so far:\n")

  for _, msg in ipairs(conversation) do
    if msg.role == "user" then
      table.insert(parts, "User: " .. msg.content .. "\n")
    else
      table.insert(parts, "Assistant: " .. msg.content .. "\n")
    end
  end

  table.insert(parts, "\nRespond to the user's latest message. ")
  table.insert(parts, "You have full context of the expedition above. ")
  table.insert(parts, "Be helpful, concise, and reference specific notes or code locations when relevant. ")
  table.insert(parts, "Use markdown formatting.")

  return table.concat(parts), M.system_prompt()
end

--- Build the summit evaluation prompt.
--- @return string prompt, string system
function M.build_summit_eval_prompt()
  local serializer = require("expedition.serializer")
  local state = serializer.serialize({ include_log = true })

  local summit = require("expedition.summit")
  local conditions = summit.list()
  local has_conditions = #conditions > 0

  local prompt = state .. [[

---

Evaluate whether this expedition is ready to be completed ("summit reached").
Consider:
- Are all waypoints done or abandoned?
- Do the field notes suggest unresolved questions?
- Is there evidence of thorough exploration?]]

  if has_conditions then
    prompt = prompt .. [[

- Evaluate each summit condition individually based on the evidence in notes and waypoint status
- Conditions already marked "met" should be assessed as met unless evidence contradicts this
- Conditions marked "open" need evidence from notes or completed waypoints to be considered met]]
  end

  prompt = prompt .. [=[


Respond with JSON in this exact format:
```json
{
  "ready": true,
  "confidence": 0.85,
  "reasoning": "Explanation of the evaluation",
  "remaining": ["Any remaining items to address"]]=]

  if has_conditions then
    prompt = prompt .. [=[,
  "conditions": [
    {
      "id": "condition-id",
      "assessment": "met",
      "reasoning": "Why this condition is or is not met"
    }
  ]]=]
  end

  prompt = prompt .. [[

}
```

Rules:
- "ready" is a boolean: true if the expedition can be considered complete
- "confidence" is a number between 0 and 1
- "remaining" is an array of strings describing unfinished items (empty if ready)
- Be honest -- if there are open questions in the notes, flag them]]

  if has_conditions then
    prompt = prompt .. [[

- "conditions" array must include an assessment for each summit condition
- Each assessment should be "met", "not_met", or "abandoned"
- All conditions must be met or abandoned for the expedition to be ready]]
  end

  return prompt, M.system_prompt()
end

return M
