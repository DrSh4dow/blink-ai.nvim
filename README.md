# blink-ai.nvim

blink-ai.nvim is a Neovim plugin that injects AI completions into the
blink.cmp completion menu.

## Requirements

- Neovim 0.10+
- `curl`
- `saghen/blink.cmp`

## Install (lazy.nvim)

```lua
{
  "your-username/blink-ai.nvim",
  dependencies = { "saghen/blink.cmp" },
  opts = {
    provider = "openai",
    providers = {
      openai = {
        model = "gpt-4o-mini",
      },
    },
  },
  specs = {
    {
      "saghen/blink.cmp",
      optional = true,
      opts = {
        sources = {
          default = { "lsp", "path", "snippets", "buffer", "ai" },
          providers = {
            ai = {
              name = "AI",
              module = "blink-ai",
              async = true,
              timeout_ms = 5000,
              score_offset = 10,
            },
          },
        },
      },
    },
  },
}
```

## Setup

```lua
require("blink-ai").setup({
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
  },
  system_prompt = nil,
  transform_items = nil,
})
```

OpenAI credentials are read from `OPENAI_API_KEY` unless explicitly set in
`providers.openai.api_key`.

## Providers

- `openai` is implemented with streaming.
- `anthropic`, `ollama`, `openai_compatible`, and `fim` are scaffolded but not
  implemented yet.

## License

MIT
