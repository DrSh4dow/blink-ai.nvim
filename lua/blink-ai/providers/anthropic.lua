local prompt = require("blink-ai.prompt")
local request = require("blink-ai.request")

local M = {
  name = "anthropic",
  supports_n = false,
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
    key = os.getenv("ANTHROPIC_API_KEY")
  end
  return key
end

local function extract_delta_text(decoded)
  if type(decoded.delta) == "table" and type(decoded.delta.text) == "string" then
    return decoded.delta.text
  end
  if type(decoded.content_block) == "table" and type(decoded.content_block.text) == "string" then
    return decoded.content_block.text
  end
  if type(decoded.completion) == "string" then
    return decoded.completion
  end
  return nil
end

function M.complete(ctx, on_chunk, on_done, on_error, config)
  local p_opts = provider_opts(config)
  local api_key = resolve_api_key(p_opts)
  if not api_key or api_key == "" then
    if on_error then
      on_error({
        key = "anthropic:api_key_missing",
        message = "Anthropic API key is missing (set ANTHROPIC_API_KEY or providers.anthropic.api_key)",
      })
    end
    if on_done then
      on_done()
    end
    return function() end
  end

  local body = {
    model = p_opts.model or "claude-sonnet-4-20250514",
    max_tokens = config.max_tokens,
    temperature = p_opts.temperature or 0.1,
    stream = true,
    system = prompt.system_prompt(ctx, config),
    messages = prompt.anthropic_messages(ctx),
  }
  if p_opts.extra_body and next(p_opts.extra_body) ~= nil then
    body = vim.tbl_deep_extend("force", body, p_opts.extra_body)
  end

  local headers = vim.tbl_extend("force", {
    ["x-api-key"] = api_key,
    ["anthropic-version"] = p_opts.api_version or "2023-06-01",
    ["content-type"] = "application/json",
  }, p_opts.headers or {})

  local buffers = {}

  local function handle_data(data)
    local ok, decoded = pcall(vim.json.decode, data)
    if not ok or type(decoded) ~= "table" then
      return
    end
    if decoded.type == "error" or type(decoded.error) == "table" then
      local message = "Anthropic request failed"
      if type(decoded.error) == "table" then
        message = decoded.error.message or message
      elseif type(decoded.message) == "string" then
        message = decoded.message
      end
      if on_error then
        on_error({ key = "anthropic:api_error", message = message })
      end
      return
    end

    local text = extract_delta_text(decoded)
    if not text or text == "" then
      return
    end
    buffers[1] = (buffers[1] or "") .. text
    if on_chunk then
      on_chunk(buffers)
    end
  end

  return request.stream({
    method = "POST",
    url = p_opts.endpoint or "https://api.anthropic.com/v1/messages",
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
