local prompt = require("blink-ai.prompt")
local request = require("blink-ai.request")

local M = {
  name = "openai",
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
    key = os.getenv("BLINK_OPENAI_API_KEY")
      or os.getenv("OPENAI_API_KEY")
      or os.getenv("AVANTE_OPENAI_API_KEY")
  end
  return key
end

local function is_gpt5_model(model)
  return type(model) == "string" and model:find("^gpt%-5") ~= nil
end

local function append_text(buffers, text)
  if type(text) ~= "string" or text == "" then
    return false
  end
  buffers[1] = (buffers[1] or "") .. text
  return true
end

local function collect_output_text(output)
  if type(output) ~= "table" then
    return nil
  end

  local parts = {}
  for _, item in ipairs(output) do
    if type(item) == "table" then
      if type(item.output_text) == "string" and item.output_text ~= "" then
        table.insert(parts, item.output_text)
      end
      if type(item.text) == "string" and item.text ~= "" then
        table.insert(parts, item.text)
      end
      if type(item.content) == "table" then
        for _, content_part in ipairs(item.content) do
          if type(content_part) == "table" then
            if type(content_part.text) == "string" and content_part.text ~= "" then
              table.insert(parts, content_part.text)
            elseif
              type(content_part.output_text) == "string" and content_part.output_text ~= ""
            then
              table.insert(parts, content_part.output_text)
            end
          end
        end
      end
    end
  end

  if #parts == 0 then
    return nil
  end
  return table.concat(parts, "")
end

local function response_delta_text(decoded)
  if type(decoded) ~= "table" then
    return nil
  end
  local event_type = type(decoded.type) == "string" and decoded.type or ""

  if event_type == "response.output_text.delta" then
    if type(decoded.delta) == "string" then
      return decoded.delta
    end
    if type(decoded.delta) == "table" and type(decoded.delta.text) == "string" then
      return decoded.delta.text
    end
  end

  if event_type == "response.content_part.added" then
    local part = decoded.part or decoded.content_part
    if type(part) == "table" then
      if type(part.text) == "string" then
        return part.text
      end
      if type(part.output_text) == "string" then
        return part.output_text
      end
    end
  end

  if event_type:find("delta", 1, true) then
    if type(decoded.delta) == "string" then
      return decoded.delta
    end
    if type(decoded.delta) == "table" and type(decoded.delta.text) == "string" then
      return decoded.delta.text
    end
  end

  return nil
end

local function response_final_text(decoded)
  if type(decoded) ~= "table" then
    return nil
  end
  if type(decoded.output_text) == "string" and decoded.output_text ~= "" then
    return decoded.output_text
  end
  if type(decoded.output) == "table" then
    local text = collect_output_text(decoded.output)
    if text and text ~= "" then
      return text
    end
  end
  if type(decoded.response) == "table" then
    if type(decoded.response.output_text) == "string" and decoded.response.output_text ~= "" then
      return decoded.response.output_text
    end
    if type(decoded.response.output) == "table" then
      local text = collect_output_text(decoded.response.output)
      if text and text ~= "" then
        return text
      end
    end
  end
  return nil
end

function M.complete(ctx, on_chunk, on_done, on_error, config)
  local p_opts = provider_opts(config)
  local api_key = resolve_api_key(p_opts)
  if not api_key or api_key == "" then
    if on_error then
      on_error({
        key = "openai:api_key_missing",
        message = "OpenAI API key is missing (set providers.openai.api_key or BLINK_OPENAI_API_KEY/OPENAI_API_KEY)",
      })
    end
    if on_done then
      on_done()
    end
    return function() end
  end

  local model = p_opts.model or "gpt-4o-mini"
  local body = {
    model = model,
    instructions = prompt.system_prompt(ctx, config),
    input = prompt.response_input(ctx),
    stream = true,
    max_output_tokens = config.max_tokens,
  }

  if type(p_opts.reasoning) == "table" then
    body.reasoning = p_opts.reasoning
  elseif is_gpt5_model(model) then
    body.reasoning = { effort = "minimal" }
  end

  if type(p_opts.text) == "table" then
    body.text = p_opts.text
  elseif is_gpt5_model(model) then
    body.text = { verbosity = "low" }
  end

  if type(p_opts.temperature) == "number" then
    body.temperature = p_opts.temperature
  end
  if p_opts.extra_body and next(p_opts.extra_body) ~= nil then
    body = vim.tbl_deep_extend("force", body, p_opts.extra_body)
  end

  local headers = vim.tbl_extend("force", {
    ["Authorization"] = "Bearer " .. api_key,
    ["Content-Type"] = "application/json",
  }, p_opts.headers or {})

  local buffers = {}
  local streamed_delta = false
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

    if decoded.type == "response.error" or decoded.type == "error" then
      local message = decoded.message
      if type(message) ~= "string" or message == "" then
        message = "OpenAI request failed"
      end
      if on_error then
        on_error({ key = "openai:api_error", message = message })
      end
      return
    end

    local delta_text = response_delta_text(decoded)
    if append_text(buffers, delta_text) then
      streamed_delta = true
      if on_chunk then
        on_chunk(buffers)
      end
      return
    end

    if not streamed_delta then
      local final_text = response_final_text(decoded)
      if type(final_text) == "string" and final_text ~= "" then
        if buffers[1] ~= final_text then
          buffers[1] = final_text
          if on_chunk then
            on_chunk(buffers)
          end
        end
      end
    end
  end

  return request.stream({
    method = "POST",
    url = p_opts.endpoint or "https://api.openai.com/v1/responses",
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
