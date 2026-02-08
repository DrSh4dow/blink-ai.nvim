local prompt = require("blink-ai.prompt")
local request = require("blink-ai.request")

local M = {
  name = "fim",
  supports_n = true,
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

local function resolve_api_key(p_opts)
  local key = p_opts.api_key
  if not key or key == "" then
    key = os.getenv("FIM_API_KEY")
  end
  return key
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
  if not p_opts.endpoint or p_opts.endpoint == "" then
    if on_error then
      on_error({
        key = "fim:endpoint_missing",
        message = "FIM endpoint is required (providers.fim.endpoint)",
      })
    end
    if on_done then
      on_done()
    end
    return function() end
  end

  local fim_prompt = prompt.fim_prompt(ctx, p_opts.fim_tokens)
  local body = {
    model = p_opts.model,
    prompt = fim_prompt,
    stream = true,
    max_tokens = config.max_tokens,
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
    local decoded = decode_chunk(data)
    if not decoded then
      return
    end
    if decoded.error then
      if on_error then
        on_error({ key = "fim:error", message = tostring(decoded.error) })
      end
      return
    end

    local updated = false
    if type(decoded.choices) == "table" then
      for _, choice in ipairs(decoded.choices) do
        local text = choice.text
        if type(choice.delta) == "table" and type(choice.delta.content) == "string" then
          text = choice.delta.content
        end
        if type(text) == "string" and text ~= "" then
          local idx = (choice.index or 0) + 1
          buffers[idx] = (buffers[idx] or "") .. text
          updated = true
        end
      end
    elseif type(decoded.completion) == "string" then
      buffers[1] = (buffers[1] or "") .. decoded.completion
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
