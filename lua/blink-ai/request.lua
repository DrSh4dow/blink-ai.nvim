local M = {}

local function build_headers(headers)
  local args = {}
  for name, value in pairs(headers or {}) do
    table.insert(args, "-H")
    table.insert(args, string.format("%s: %s", name, value))
  end
  return args
end

function M.create_sse_parser(on_data, on_done)
  local buffer = ""
  local done = false

  return function(chunk)
    if done or not chunk or chunk == "" then
      return
    end
    buffer = buffer .. chunk
    buffer = buffer:gsub("\r\n", "\n")

    while true do
      local event_end = buffer:find("\n\n", 1, true)
      if not event_end then
        break
      end

      local event = buffer:sub(1, event_end - 1)
      buffer = buffer:sub(event_end + 2)

      local data_lines = {}
      for line in event:gmatch("[^\n]+") do
        if line:sub(1, 5) == "data:" then
          table.insert(data_lines, vim.trim(line:sub(6)))
        end
      end
      if #data_lines > 0 then
        local data = table.concat(data_lines, "\n")
        if data == "[DONE]" then
          done = true
          if on_done then
            on_done()
          end
          return
        end
        if data ~= "" and on_data then
          on_data(data)
        end
      end
    end
  end
end

function M.stream(opts)
  if not vim.system then
    if opts.on_error then
      opts.on_error({
        key = "request:vim_system_missing",
        message = "Neovim 0.10+ is required for vim.system",
      })
    end
    if opts.on_done then
      opts.on_done()
    end
    return function() end
  end

  if vim.fn.executable("curl") ~= 1 then
    if opts.on_error then
      opts.on_error({ key = "request:curl_missing", message = "curl is required for blink-ai" })
    end
    if opts.on_done then
      opts.on_done()
    end
    return function() end
  end

  local method = opts.method or "POST"
  local cmd = { "curl", "-sS", "-N", "-X", method }
  for _, arg in ipairs(build_headers(opts.headers)) do
    table.insert(cmd, arg)
  end
  if opts.body then
    table.insert(cmd, "--data-binary")
    table.insert(cmd, "@-")
  end
  table.insert(cmd, opts.url)

  local done = false
  local cancelled = false
  local error_sent = false
  local timeout_timer

  local function on_done_once()
    if done then
      return
    end
    done = true
    if timeout_timer and not timeout_timer:is_closing() then
      timeout_timer:stop()
    end
    if opts.on_done then
      opts.on_done()
    end
  end

  local sse = M.create_sse_parser(opts.on_chunk, on_done_once)

  local function emit_error(err)
    if error_sent then
      return
    end
    error_sent = true
    if opts.on_error then
      opts.on_error(err)
    end
  end

  local handle = vim.system(cmd, {
    text = true,
    stdin = opts.body,
    stdout = function(_, data)
      if cancelled then
        return
      end
      if data and data ~= "" then
        sse(data)
      end
    end,
    stderr = function(_, data)
      if cancelled then
        return
      end
      if data and data ~= "" then
        emit_error({ key = "request:stderr", message = vim.trim(data) })
      end
    end,
  }, function(obj)
    if cancelled then
      return
    end
    if obj.code ~= 0 then
      emit_error({
        key = "request:exit_code:" .. tostring(obj.code),
        message = "Request failed with exit code " .. obj.code,
      })
    end
    on_done_once()
  end)

  if opts.timeout_ms and opts.timeout_ms > 0 then
    timeout_timer = vim.loop.new_timer()
    timeout_timer:start(opts.timeout_ms, 0, function()
      vim.schedule(function()
        if cancelled then
          return
        end
        cancelled = true
        if handle and handle.kill then
          handle:kill(15)
        end
        emit_error({ key = "request:timeout", message = "Request timed out" })
        on_done_once()
      end)
    end)
  end

  return function()
    if cancelled then
      return
    end
    cancelled = true
    if timeout_timer and not timeout_timer:is_closing() then
      timeout_timer:stop()
    end
    if handle and handle.kill then
      handle:kill(15)
    end
  end
end

return M
