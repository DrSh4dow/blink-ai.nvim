local M = {}

M.defaults = {
  provider = "openai",
  debounce_ms = 300,
  max_tokens = 256,
  n_completions = 3,
  context = {
    before_cursor_lines = 50,
    after_cursor_lines = 20,
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
      extra_body = {},
    },
    anthropic = {
      api_key = nil,
      model = "claude-sonnet-4-20250514",
      endpoint = "https://api.anthropic.com/v1/messages",
      temperature = 0.1,
      extra_body = {},
    },
    ollama = {
      model = "qwen2.5-coder:7b",
      endpoint = "http://localhost:11434/v1/chat/completions",
      extra_body = {},
    },
    openai_compatible = {
      api_key = nil,
      model = "",
      endpoint = "",
      temperature = 0.1,
      extra_body = {},
    },
    fim = {
      api_key = nil,
      model = "",
      endpoint = "",
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

return M
