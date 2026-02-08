local prompt = require("blink-ai.prompt")
local request = require("blink-ai.request")

local M = {
  name = "openai_compatible",
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
    key = os.getenv("OPENAI_COMPATIBLE_API_KEY") or os.getenv("OPENAI_API_KEY")
  end
  return key
end

local function append_choice_text(buffers, choice)
  local text = nil
  if type(choice.delta) == "table" and type(choice.delta.content) == "string" then
    text = choice.delta.content
  elseif type(choice.message) == "table" and type(choice.message.content) == "string" then
    text = choice.message.content
  elseif type(choice.text) == "string" then
    text = choice.text
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
  if not p_opts.endpoint or p_opts.endpoint == "" then
    if on_error then
      on_error({
        key = "openai_compatible:endpoint_missing",
        message = "OpenAI-compatible endpoint is required (providers.openai_compatible.endpoint)",
      })
    end
    if on_done then
      on_done()
    end
    return function() end
  end

  local body = {
    model = p_opts.model,
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
    ["Content-Type"] = "application/json",
  }, p_opts.headers or {})

  local api_key = resolve_api_key(p_opts)
  if api_key and api_key ~= "" then
    headers.Authorization = "Bearer " .. api_key
  end

  local buffers = {}

  local function handle_data(data)
    local ok, decoded = pcall(vim.json.decode, data)
    if not ok or type(decoded) ~= "table" then
      return
    end
    if type(decoded.error) == "table" then
      if on_error then
        on_error({
          key = "openai_compatible:api_error",
          message = decoded.error.message or "Request failed",
        })
      end
      return
    end
    local choices = decoded.choices or {}
    local updated = false
    for _, choice in ipairs(choices) do
      updated = append_choice_text(buffers, choice) or updated
    end
    if updated and on_chunk then
      on_chunk(buffers)
    end
  end

  return request.stream({
    method = "POST",
    url = p_opts.endpoint,
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
