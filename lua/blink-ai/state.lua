local M = {}

local enabled = true
local active_cancel = nil

M.stats = {
  enabled = false,
  requests = 0,
  successes = 0,
  errors = 0,
  cancels = 0,
  in_flight = false,
  last_duration_ms = nil,
  last_provider = nil,
  last_model = nil,
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
  M.stats.in_flight = false
end

function M.cancel(reason)
  if active_cancel then
    active_cancel()
    active_cancel = nil
    if M.stats.enabled then
      M.stats.cancels = M.stats.cancels + 1
    end
    M.stats.in_flight = false
    if reason and reason ~= "" then
      M.last_error = "Cancelled: " .. reason
    end
    return true
  end
  return false
end

function M.record_request(provider, model)
  if not M.stats.enabled then
    return nil
  end
  M.stats.requests = M.stats.requests + 1
  M.stats.in_flight = true
  M.stats.last_provider = provider
  M.stats.last_model = model
  return vim.loop.hrtime()
end

function M.record_success(start_ns)
  if not M.stats.enabled then
    return
  end
  if start_ns then
    M.stats.last_duration_ms = math.floor((vim.loop.hrtime() - start_ns) / 1e6)
  end
  M.stats.successes = M.stats.successes + 1
  M.stats.in_flight = false
end

function M.record_error(start_ns, err)
  M.last_error = err
  if not M.stats.enabled then
    return
  end
  if start_ns then
    M.stats.last_duration_ms = math.floor((vim.loop.hrtime() - start_ns) / 1e6)
  end
  M.stats.errors = M.stats.errors + 1
  M.stats.in_flight = false
end

function M.set_stats_enabled(enabled_stats)
  M.stats.enabled = not not enabled_stats
  if not M.stats.enabled then
    M.stats.in_flight = false
  end
end

function M.reset_stats()
  M.stats.requests = 0
  M.stats.successes = 0
  M.stats.errors = 0
  M.stats.cancels = 0
  M.stats.in_flight = false
  M.stats.last_duration_ms = nil
  M.stats.last_provider = nil
  M.stats.last_model = nil
  M.last_error = nil
end

return M
