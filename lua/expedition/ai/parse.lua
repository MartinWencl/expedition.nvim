--- AI response parsing for expedition.nvim
--- Extracts JSON from AI responses and validates structures.
local M = {}

--- Extract JSON from a text response.
--- Tries: ```json fence, bare ``` fence, then raw JSON.
--- @param text string
--- @return table?, string?
function M.extract_json(text)
  -- Try ```json fenced block
  local fenced = text:match("```json%s*\n(.-)```")
  if fenced then
    local ok, result = pcall(vim.json.decode, fenced)
    if ok then return result end
  end

  -- Try bare ``` fenced block
  local bare = text:match("```%s*\n(.-)```")
  if bare then
    local ok, result = pcall(vim.json.decode, bare)
    if ok then return result end
  end

  -- Try raw JSON (find first { or [)
  local start = text:find("[%{%[]")
  if start then
    -- Find matching closing bracket
    local opener = text:sub(start, start)
    local closer = opener == "{" and "}" or "]"
    local depth = 0
    local in_string = false
    local escape = false
    for i = start, #text do
      local c = text:sub(i, i)
      if escape then
        escape = false
      elseif c == "\\" and in_string then
        escape = true
      elseif c == '"' then
        in_string = not in_string
      elseif not in_string then
        if c == opener then
          depth = depth + 1
        elseif c == closer then
          depth = depth - 1
          if depth == 0 then
            local raw = text:sub(start, i)
            local ok, result = pcall(vim.json.decode, raw)
            if ok then return result end
            break
          end
        end
      end
    end
  end

  return nil, "No valid JSON found in response"
end

--- Parse an AI response as a route proposal.
--- @param text string
--- @return expedition.AiProposal?, string?
function M.parse_proposal(text)
  local data, err = M.extract_json(text)
  if not data then
    return nil, err
  end

  -- Validate structure
  local waypoints = data.waypoints
  if type(waypoints) ~= "table" or #waypoints == 0 then
    return nil, "Proposal must contain a non-empty 'waypoints' array"
  end

  for i, wp in ipairs(waypoints) do
    if type(wp.title) ~= "string" or wp.title == "" then
      return nil, "Waypoint " .. i .. " missing required 'title' field"
    end
    wp.description = wp.description or ""
    wp.reasoning = wp.reasoning or ""
    wp.depends_on_titles = wp.depends_on_titles or wp.depends_on or {}
    if type(wp.depends_on_titles) ~= "table" then
      wp.depends_on_titles = {}
    end
  end

  return {
    waypoints = waypoints,
    summary = data.summary or "",
  }
end

--- Parse an AI response as a summit evaluation.
--- @param text string
--- @return expedition.SummitEvaluation?, string?
function M.parse_summit_eval(text)
  local data, err = M.extract_json(text)
  if not data then
    return nil, err
  end

  if type(data.ready) ~= "boolean" then
    return nil, "Summit evaluation must contain a boolean 'ready' field"
  end

  return {
    ready = data.ready,
    confidence = tonumber(data.confidence) or 0,
    reasoning = data.reasoning or "",
    remaining = data.remaining or {},
  }
end

return M
