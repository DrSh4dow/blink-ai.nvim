local M = {}

local function build_headers(headers)
  local args = {}
  for name, value in pairs(headers or {}) do
    table.insert(args, "-H")
    table.insert(args, string.format("%s: %s", name, value))
  end
  return args
end

local function stop_timer(timer)
  if not timer then
    return
  end
  if not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

local function normalize_error(err)
  if type(err) == "table" then
    return err
  end
  return {
    key = "request:error",
    message = tostring(err),
  }
end

local function is_rate_limit_error(err)
  local normalized = normalize_error(err)
  if normalized.http_status == 429 then
    return true
  end
  if type(normalized.code) == "number" and normalized.code == 429 then
    return true
  end
  local message = string.lower(normalized.message or "")
  return message:find("429", 1, true) ~= nil or message:find("rate limit", 1, true) ~= nil
end

local function retry_delay_ms(base_ms, attempt)
  local exponential = base_ms * (2 ^ math.max(0, attempt - 1))
  local jitter = math.random(0, math.max(50, math.floor(base_ms / 2)))
  return exponential + jitter
end

function M.create_sse_parser(on_data, on_done)
  local buffer = ""
  local done = false

  local function parse_events(final_flush)
    while true do
      local event_end = buffer:find("\n\n", 1, true)
      if not event_end then
        if final_flush and buffer ~= "" then
          buffer = buffer .. "\n\n"
          final_flush = false
        else
          break
        end
      end

      event_end = buffer:find("\n\n", 1, true)
      if not event_end then
        break
      end

      local event = buffer:sub(1, event_end - 1)
      buffer = buffer:sub(event_end + 2)

      local data_lines = {}
      for line in event:gmatch("[^\n]+") do
        if line:sub(1, 1) ~= ":" and line:sub(1, 5) == "data:" then
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

  return {
    push = function(chunk)
      if done or not chunk or chunk == "" then
        return
      end
      buffer = buffer .. chunk
      buffer = buffer:gsub("\r\n", "\n")
      parse_events(false)
    end,
    finish = function()
      if done then
        return
      end
      parse_events(true)
    end,
    is_done = function()
      return done
    end,
  }
end

function M.create_jsonl_parser(on_data, on_done)
  local buffer = ""
  local done = false

  local function decode_line(line)
    local text = vim.trim(line or "")
    if text == "" then
      return
    end
    if text:sub(1, 5) == "data:" then
      text = vim.trim(text:sub(6))
    end
    if text == "" then
      return
    end
    if text == "[DONE]" then
      done = true
      if on_done then
        on_done()
      end
      return
    end
    if on_data then
      on_data(text)
    end
  end

  local function parse_lines(final_flush)
    while true do
      local newline = buffer:find("\n", 1, true)
      if not newline then
        if final_flush and buffer ~= "" then
          decode_line(buffer)
          buffer = ""
        end
        break
      end
      local line = buffer:sub(1, newline - 1)
      buffer = buffer:sub(newline + 1)
      decode_line(line)
    end
  end

  return {
    push = function(chunk)
      if done or not chunk or chunk == "" then
        return
      end
      buffer = buffer .. chunk
      buffer = buffer:gsub("\r\n", "\n")
      parse_lines(false)
    end,
    finish = function()
      if done then
        return
      end
      parse_lines(true)
    end,
    is_done = function()
      return done
    end,
  }
end

local function create_stream_parser(mode, on_data, on_done)
  if mode == "jsonl" then
    return M.create_jsonl_parser(on_data, on_done)
  end
  return M.create_sse_parser(on_data, on_done)
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
  local stream_mode = opts.stream_mode or "sse"
  local max_attempts = math.max(1, opts.max_attempts or 1)
  local retry_on_rate_limit = opts.retry_on_rate_limit ~= false
  local retry_backoff_base_ms = math.max(100, opts.retry_backoff_base_ms or 300)

  local cancelled = false
  local finished = false
  local attempt = 0
  local handle
  local timeout_timer
  local retry_timer

  local function on_done_once()
    if finished then
      return
    end
    finished = true
    stop_timer(timeout_timer)
    stop_timer(retry_timer)
    timeout_timer = nil
    retry_timer = nil
    if opts.on_done then
      opts.on_done()
    end
  end

  local function emit_error(err)
    if opts.on_error then
      opts.on_error(normalize_error(err))
    end
  end

  local function should_retry(err)
    if cancelled or finished then
      return false
    end
    if attempt >= max_attempts then
      return false
    end
    if not retry_on_rate_limit then
      return false
    end
    return is_rate_limit_error(err)
  end

  local start_attempt
  start_attempt = function()
    if cancelled or finished then
      return
    end

    attempt = attempt + 1
    stop_timer(timeout_timer)
    timeout_timer = nil

    local cmd = { "curl", "-sS", "-N", "--fail", "-X", method }
    for _, arg in ipairs(build_headers(opts.headers)) do
      table.insert(cmd, arg)
    end
    if opts.body then
      table.insert(cmd, "--data-binary")
      table.insert(cmd, "@-")
    end
    table.insert(cmd, opts.url)

    local stderr_parts = {}
    local parser = create_stream_parser(stream_mode, opts.on_chunk, on_done_once)

    handle = vim.system(cmd, {
      text = true,
      stdin = opts.body,
      stdout = function(_, data)
        if cancelled or finished then
          return
        end
        if data and data ~= "" then
          parser.push(data)
        end
      end,
      stderr = function(_, data)
        if cancelled or finished then
          return
        end
        if data and data ~= "" then
          table.insert(stderr_parts, data)
        end
      end,
    }, function(obj)
      vim.schedule(function()
        if cancelled or finished then
          return
        end

        stop_timer(timeout_timer)
        timeout_timer = nil

        parser.finish()

        if obj.code == 0 then
          on_done_once()
          return
        end

        local message = vim.trim(table.concat(stderr_parts, " "))
        if message == "" then
          message = "Request failed with exit code " .. tostring(obj.code)
        end

        local err = {
          key = "request:exit_code:" .. tostring(obj.code),
          message = message,
          code = obj.code,
        }

        if message:find("429", 1, true) then
          err.http_status = 429
          err.key = "request:http_429"
        end

        if should_retry(err) then
          local delay = retry_delay_ms(retry_backoff_base_ms, attempt)
          retry_timer = vim.loop.new_timer()
          retry_timer:start(delay, 0, function()
            vim.schedule(function()
              stop_timer(retry_timer)
              retry_timer = nil
              start_attempt()
            end)
          end)
          return
        end

        emit_error(err)
        on_done_once()
      end)
    end)

    if opts.timeout_ms and opts.timeout_ms > 0 then
      timeout_timer = vim.loop.new_timer()
      timeout_timer:start(opts.timeout_ms, 0, function()
        vim.schedule(function()
          if cancelled or finished then
            return
          end
          if handle and handle.kill then
            handle:kill(15)
          end
          emit_error({ key = "request:timeout", message = "Request timed out" })
          on_done_once()
        end)
      end)
    end
  end

  start_attempt()

  return function()
    if cancelled then
      return
    end
    cancelled = true
    stop_timer(timeout_timer)
    stop_timer(retry_timer)
    timeout_timer = nil
    retry_timer = nil
    if handle and handle.kill then
      handle:kill(15)
    end
  end
end

return M
