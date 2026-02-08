local prompt = require("blink-ai.prompt")
local request = require("blink-ai.request")

local M = {
  name = "ollama",
  supports_n = false,
  stream_mode = "jsonl",
}

local opts = {}

function M.setup(new_opts)
  opts = new_opts or {}
end

local function provider_opts(runtime_cfg)
  local runtime_opts = {}
  if runtime_cfg and runtime_cfg.effective_provider == M.name then
    runtime_opts = runtime_cfg.effective_provider_config or {}
  end
  return vim.tbl_deep_extend("force", {}, opts, runtime_opts)
end

local function build_body(ctx, config, p_opts)
  local endpoint = p_opts.endpoint or "http://localhost:11434/v1/chat/completions"
  if endpoint:find("/api/generate", 1, true) then
    local combined = (ctx.context_before_cursor or "")
      .. "<cursor>"
      .. (ctx.context_after_cursor or "")
    local body = {
      model = p_opts.model or "qwen2.5-coder:7b",
      prompt = combined,
      stream = true,
      options = {
        temperature = p_opts.temperature or 0.1,
      },
    }
    if p_opts.extra_body and next(p_opts.extra_body) ~= nil then
      body = vim.tbl_deep_extend("force", body, p_opts.extra_body)
    end
    return body
  end

  local body = {
    model = p_opts.model or "qwen2.5-coder:7b",
    messages = prompt.chat_messages(ctx, config),
    stream = true,
    max_tokens = config.max_tokens,
    temperature = p_opts.temperature or 0.1,
  }
  if p_opts.extra_body and next(p_opts.extra_body) ~= nil then
    body = vim.tbl_deep_extend("force", body, p_opts.extra_body)
  end
  return body
end

local function decode_chunk(data)
  local text = vim.trim(data or "")
  if text == "" then
    return nil
  end
  if text:sub(1, 5) == "data:" then
    text = vim.trim(text:sub(6))
  end
  if text == "" or text == "[DONE]" then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, text)
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

function M.complete(ctx, on_chunk, on_done, on_error, config)
  local p_opts = provider_opts(config)
  local endpoint = p_opts.endpoint or "http://localhost:11434/v1/chat/completions"
  local body = build_body(ctx, config, p_opts)
  local headers = vim.tbl_extend("force", {
    ["Content-Type"] = "application/json",
  }, p_opts.headers or {})

  local buffers = {}

  local function handle_data(data)
    local decoded = decode_chunk(data)
    if not decoded then
      return
    end
    if decoded.error then
      if on_error then
        on_error({ key = "ollama:error", message = tostring(decoded.error) })
      end
      return
    end

    local updated = false
    if type(decoded.choices) == "table" then
      for _, choice in ipairs(decoded.choices) do
        local delta = choice.delta or {}
        local text = delta.content or choice.text
        if type(text) == "string" and text ~= "" then
          local idx = (choice.index or 0) + 1
          buffers[idx] = (buffers[idx] or "") .. text
          updated = true
        end
      end
    elseif type(decoded.message) == "table" and type(decoded.message.content) == "string" then
      buffers[1] = (buffers[1] or "") .. decoded.message.content
      updated = true
    elseif type(decoded.response) == "string" then
      buffers[1] = (buffers[1] or "") .. decoded.response
      updated = true
    end

    if updated and on_chunk then
      on_chunk(buffers)
    end
  end

  return request.stream({
    method = "POST",
    url = endpoint,
    headers = headers,
    body = vim.json.encode(body),
    on_chunk = handle_data,
    on_done = on_done,
    on_error = on_error,
    timeout_ms = config.timeout_ms,
    stream_mode = p_opts.stream_mode or M.stream_mode,
    max_attempts = 2,
    retry_on_rate_limit = true,
    retry_backoff_base_ms = 300,
  })
end

return M
