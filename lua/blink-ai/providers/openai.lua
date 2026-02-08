local prompt = require("blink-ai.prompt")
local request = require("blink-ai.request")

local M = {
  name = "openai",
  supports_n = true,
  stream_mode = "sse",
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

local function resolve_api_key(p_opts)
  local key = p_opts.api_key
  if not key or key == "" then
    key = os.getenv("BLINK_OPENAI_API_KEY")
  end
  return key
end

local function append_content(buffers, choice)
  local content = nil
  if type(choice.delta) == "table" then
    content = choice.delta.content
  end
  if (not content or content == "") and type(choice.message) == "table" then
    content = choice.message.content
  end
  if (not content or content == "") and type(choice.text) == "string" then
    content = choice.text
  end

  local text = nil
  if type(content) == "string" then
    text = content
  elseif type(content) == "table" then
    local parts = {}
    for _, part in ipairs(content) do
      if type(part) == "string" then
        table.insert(parts, part)
      elseif type(part) == "table" and type(part.text) == "string" then
        table.insert(parts, part.text)
      end
    end
    text = table.concat(parts, "")
  end

  if not text or text == "" then
    return false
  end

  local idx = (choice.index or 0) + 1
  buffers[idx] = (buffers[idx] or "") .. text
  return true
end

function M.complete(ctx, on_chunk, on_done, on_error, config)
  local p_opts = provider_opts(config)
  local api_key = resolve_api_key(p_opts)
  if not api_key or api_key == "" then
    if on_error then
      on_error({
        key = "openai:api_key_missing",
        message = "OpenAI API key is missing (set BLINK_OPENAI_API_KEY or providers.openai.api_key)",
      })
    end
    if on_done then
      on_done()
    end
    return function() end
  end

  local body = {
    model = p_opts.model or "gpt-4o-mini",
    messages = prompt.chat_messages(ctx, config),
    stream = true,
    max_tokens = config.max_tokens,
    temperature = p_opts.temperature or 0.1,
    n = math.max(1, config.n_completions or 1),
  }
  if p_opts.extra_body and next(p_opts.extra_body) ~= nil then
    body = vim.tbl_deep_extend("force", body, p_opts.extra_body)
  end

  local headers = vim.tbl_extend("force", {
    ["Authorization"] = "Bearer " .. api_key,
    ["Content-Type"] = "application/json",
  }, p_opts.headers or {})

  local buffers = {}
  local function handle_data(data)
    local ok, decoded = pcall(vim.json.decode, data)
    if not ok or type(decoded) ~= "table" then
      return
    end

    if type(decoded.error) == "table" then
      local message = decoded.error.message or "OpenAI request failed"
      if on_error then
        on_error({ key = "openai:api_error", message = message })
      end
      return
    end

    local choices = decoded.choices or {}
    local updated = false
    for _, choice in ipairs(choices) do
      updated = append_content(buffers, choice) or updated
    end
    if updated and on_chunk then
      on_chunk(buffers)
    end
  end

  return request.stream({
    method = "POST",
    url = p_opts.endpoint or "https://api.openai.com/v1/chat/completions",
    headers = headers,
    body = vim.json.encode(body),
    on_chunk = handle_data,
    on_done = on_done,
    on_error = on_error,
    timeout_ms = config.timeout_ms,
    stream_mode = p_opts.stream_mode or M.stream_mode,
    max_attempts = 3,
    retry_on_rate_limit = true,
    retry_backoff_base_ms = 300,
  })
end

return M
