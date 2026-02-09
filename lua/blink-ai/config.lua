local M = {}

M.defaults = {
  provider = "openai",
  provider_overrides = {},
  performance_profile = "fast",
  profiles = {
    fast = {
      debounce_ms = 80,
      max_tokens = 96,
      before_cursor_lines = 20,
      after_cursor_lines = 8,
    },
    balanced = {
      debounce_ms = 180,
      max_tokens = 160,
      before_cursor_lines = 40,
      after_cursor_lines = 16,
    },
    quality = {
      debounce_ms = 300,
      max_tokens = 256,
      before_cursor_lines = 60,
      after_cursor_lines = 24,
    },
  },
  debounce_ms = 300,
  max_tokens = 256,
  n_completions = 1,
  suggestion_mode = "raw",
  context = {
    before_cursor_lines = 50,
    after_cursor_lines = 20,
    enable_treesitter = false,
    user_context = nil,
    repo = {
      enabled = true,
      max_files = 3,
      max_lines_per_file = 80,
      max_chars_total = 6000,
      include_current_dir = true,
    },
  },
  stats = {
    enabled = false,
  },
  ui = {
    loading_placeholder = {
      enabled = true,
      watchdog_ms = 1200,
    },
  },
  filetypes = {},
  filetypes_exclude = { "TelescopePrompt", "NvimTree", "neo-tree", "oil" },
  notify_on_error = true,
  providers = {
    openai = {
      api_key = nil,
      model = "gpt-4o-mini",
      fast_model = "gpt-5-mini",
      model_strategy = "fast_for_completion",
      endpoint = "https://api.openai.com/v1/responses",
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

local function active_profile(options)
  if type(options) ~= "table" then
    return nil
  end
  local profiles = options.profiles or {}
  local profile_name = options.performance_profile
  if type(profile_name) ~= "string" or profile_name == "" then
    return nil
  end
  local profile = profiles[profile_name]
  if type(profile) ~= "table" then
    return nil
  end
  return profile
end

local function apply_profile_defaults(options, user_opts)
  local profile = active_profile(options)
  if not profile then
    return
  end

  local raw = user_opts or {}
  if raw.debounce_ms == nil and type(profile.debounce_ms) == "number" then
    options.debounce_ms = profile.debounce_ms
  end
  if raw.max_tokens == nil and type(profile.max_tokens) == "number" then
    options.max_tokens = profile.max_tokens
  end

  local raw_context = type(raw.context) == "table" and raw.context or {}
  if raw_context.before_cursor_lines == nil and type(profile.before_cursor_lines) == "number" then
    options.context.before_cursor_lines = profile.before_cursor_lines
  end
  if raw_context.after_cursor_lines == nil and type(profile.after_cursor_lines) == "number" then
    options.context.after_cursor_lines = profile.after_cursor_lines
  end
end

function M.setup(opts)
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  apply_profile_defaults(merged, opts or {})
  M.options = merged
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
