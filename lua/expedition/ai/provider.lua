--- AI provider interface for expedition.nvim
--- Dispatches to backend modules based on config.
local M = {}

--- @alias expedition.AiBackend { call: fun(request: expedition.AiRequest): expedition.AiHandle?, is_available: (fun(): boolean, string?)? }

--- @class expedition.AiRequest
--- @field prompt string
--- @field system string?
--- @field on_success fun(response: string)
--- @field on_error fun(err: string)

--- @class expedition.AiHandle
--- @field cancel fun()

--- Check if AI features are available.
--- @return boolean, string?
function M.is_available()
  local config = require("expedition.config")
  if not config.val("ai.enabled") then
    return false, "AI features are disabled (set ai.enabled = true)"
  end

  local backend_name = config.val("ai.backend")
  local ok, backend = pcall(require, "expedition.ai.backend." .. backend_name)
  if not ok then
    return false, "Unknown AI backend: " .. backend_name
  end

  if backend.is_available then
    return backend.is_available()
  end

  return true
end

--- Call the AI backend with a request.
--- @param request expedition.AiRequest
--- @return expedition.AiHandle?
function M.call(request)
  local available, reason = M.is_available()
  if not available then
    request.on_error(reason or "AI not available")
    return nil
  end

  local backend_name = require("expedition.config").val("ai.backend")
  local backend = require("expedition.ai.backend." .. backend_name)
  return backend.call(request)
end

return M
