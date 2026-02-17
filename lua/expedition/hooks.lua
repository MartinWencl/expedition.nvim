--- Event dispatch system for expedition.nvim
--- Minimal but functional — every CRUD module calls dispatch() to establish
--- call sites for Phase 4 hook system.
local M = {}

--- @type table<string, { fn: function, opts: table }[]>
local _listeners = {}

--- Register a callback for an event.
--- @param event string
--- @param callback function
--- @param opts table?
--- @return function unregister function
function M.on(event, callback, opts)
  if not _listeners[event] then
    _listeners[event] = {}
  end
  local entry = { fn = callback, opts = opts or {} }
  table.insert(_listeners[event], entry)

  return function()
    local list = _listeners[event]
    if not list then return end
    for i, e in ipairs(list) do
      if e == entry then
        table.remove(list, i)
        return
      end
    end
  end
end

--- Dispatch an event to all registered callbacks.
--- Callbacks are pcall-wrapped so one failure doesn't break others.
--- @param event string
--- @param payload table?
function M.dispatch(event, payload)
  local list = _listeners[event]
  if not list then return end
  for _, entry in ipairs(list) do
    local ok, err = pcall(entry.fn, payload or {})
    if not ok then
      vim.schedule(function()
        vim.notify(
          string.format("[expedition] hook error on '%s': %s", event, err),
          vim.log.levels.WARN
        )
      end)
    end
  end
end

--- Clear listeners for a specific event, or all events if none given.
--- @param event string?
function M.clear(event)
  if event then
    _listeners[event] = nil
  else
    _listeners = {}
  end
end

return M
