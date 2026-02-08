local M = {}

local seen = {}

function M.debouncer(ms, fn)
  local timer = vim.loop.new_timer()

  local function cancel()
    if timer and not timer:is_closing() then
      timer:stop()
    end
  end

  local function call(...)
    local args = { ... }
    cancel()
    timer:start(ms, 0, function()
      vim.schedule(function()
        fn(table.unpack(args))
      end)
    end)
  end

  return { call = call, cancel = cancel }
end

function M.notify(msg, level)
  local cfg = require("blink-ai.config").get()
  if not cfg.notify_on_error then
    return
  end
  vim.notify(msg, level or vim.log.levels.WARN, { title = "blink-ai" })
end

function M.notify_once(key, msg, level)
  if seen[key] then
    return
  end
  seen[key] = true
  M.notify(msg, level)
end

return M
