local request = require("blink-ai.request")
local prompt = require("blink-ai.prompt")

local M = { name = "openai" }

local opts = {}

function M.setup(new_opts)
  opts = new_opts or {}
end

local function resolve_api_key()
  local key = opts.api_key
  if not key or key == "" then
    key = os.getenv("OPENAI_API_KEY")
  end
  return key
end

function M.complete(ctx, on_chunk, on_done, on_error, config)
  local api_key = resolve_api_key()
  if not api_key or api_key == "" then
    if on_error then
      on_error("OpenAI API key is missing (set OPENAI_API_KEY or providers.openai.api_key)")
    end
    if on_done then
      on_done()
    end
    return function() end
  end

  local body = {
    model = opts.model or "gpt-4o-mini",
    messages = prompt.chat_messages(ctx, config),
    stream = true,
    max_tokens = config.max_tokens,
    temperature = opts.temperature or 0.1,
    n = math.max(1, config.n_completions or 1),
  }

  if opts.extra_body and next(opts.extra_body) ~= nil then
    body = vim.tbl_deep_extend("force", body, opts.extra_body)
  end

  local buffers = {}

  local function handle_data(data)
    local ok, decoded = pcall(vim.json.decode, data)
    if not ok then
      return
    end
    local choices = decoded.choices or {}
    local updated = false
    for _, choice in ipairs(choices) do
      local delta = choice.delta or {}
      local text = delta.content
      if text and text ~= "" then
        local idx = (choice.index or 0) + 1
        buffers[idx] = (buffers[idx] or "") .. text
        updated = true
      end
    end
    if updated and on_chunk then
      on_chunk(buffers)
    end
  end

  return request.stream({
    method = "POST",
    url = opts.endpoint or "https://api.openai.com/v1/chat/completions",
    headers = {
      ["Authorization"] = "Bearer " .. api_key,
      ["Content-Type"] = "application/json",
    },
    body = vim.json.encode(body),
    on_chunk = handle_data,
    on_done = on_done,
    on_error = on_error,
  })
end

return M
