local M = {}

local enabled = true
local active_cancel = nil

M.stats = {
  requests = 0,
  successes = 0,
  errors = 0,
  last_duration_ms = nil,
}

M.last_error = nil

function M.is_enabled()
  return enabled
end

function M.set_enabled(value)
  enabled = not not value
end

function M.toggle()
  enabled = not enabled
  return enabled
end

function M.set_cancel(fn)
  active_cancel = fn
end

function M.clear_cancel()
  active_cancel = nil
end

function M.cancel()
  if active_cancel then
    active_cancel()
    active_cancel = nil
    return true
  end
  return false
end

function M.record_request()
  M.stats.requests = M.stats.requests + 1
  return vim.loop.hrtime()
end

function M.record_success(start_ns)
  if start_ns then
    M.stats.last_duration_ms = math.floor((vim.loop.hrtime() - start_ns) / 1e6)
  end
  M.stats.successes = M.stats.successes + 1
end

function M.record_error(start_ns, err)
  if start_ns then
    M.stats.last_duration_ms = math.floor((vim.loop.hrtime() - start_ns) / 1e6)
  end
  M.stats.errors = M.stats.errors + 1
  M.last_error = err
end

return M
