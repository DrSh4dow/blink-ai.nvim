local M = {}

M.defaults = {
  provider = "openai",
  provider_overrides = {},
  debounce_ms = 300,
  max_tokens = 256,
  n_completions = 2,
  suggestion_mode = "paired",
  context = {
    before_cursor_lines = 50,
    after_cursor_lines = 20,
    enable_treesitter = false,
    user_context = nil,
  },
  stats = {
    enabled = false,
  },
  filetypes = {},
  filetypes_exclude = { "TelescopePrompt", "NvimTree", "neo-tree", "oil" },
  notify_on_error = true,
  providers = {
    openai = {
      api_key = nil,
      model = "gpt-4o-mini",
      endpoint = "https://api.openai.com/v1/chat/completions",
      temperature = 0.1,
      headers = {},
      extra_body = {},
    },
    anthropic = {
      api_key = nil,
      model = "claude-sonnet-4-20250514",
      endpoint = "https://api.anthropic.com/v1/messages",
      temperature = 0.1,
      headers = {},
      extra_body = {},
    },
    ollama = {
      model = "qwen2.5-coder:7b",
      endpoint = "http://localhost:11434/v1/chat/completions",
      stream_mode = "jsonl",
      headers = {},
      extra_body = {},
    },
    openai_compatible = {
      api_key = nil,
      model = "",
      endpoint = "",
      temperature = 0.1,
      headers = {},
      extra_body = {},
    },
    fim = {
      api_key = nil,
      model = "",
      endpoint = "",
      fim_tokens = {
        prefix = "<prefix>",
        suffix = "<suffix>",
        middle = "<middle>",
      },
      stream_mode = "jsonl",
      headers = {},
      extra_body = {},
    },
  },
  system_prompt = nil,
  transform_items = nil,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

function M.get()
  return M.options
end

function M.set_provider(name)
  M.options.provider = name
end

function M.set_provider_model(name, model)
  if not M.options.providers[name] then
    M.options.providers[name] = {}
  end
  M.options.providers[name].model = model
end

---Resolve provider and options for a filetype, considering overrides.
---@param filetype string
---@return string provider_name
---@return table provider_opts
function M.resolve_provider(filetype)
  local provider_name = M.options.provider
  local override = M.options.provider_overrides[filetype]
  if
    type(override) == "table"
    and type(override.provider) == "string"
    and override.provider ~= ""
  then
    provider_name = override.provider
  end

  local provider_opts = vim.deepcopy(M.options.providers[provider_name] or {})
  if type(override) == "table" then
    if type(override.model) == "string" and override.model ~= "" then
      provider_opts.model = override.model
    end
    if type(override.provider_opts) == "table" then
      provider_opts = vim.tbl_deep_extend("force", provider_opts, override.provider_opts)
    end
  end

  return provider_name, provider_opts
end

return M
