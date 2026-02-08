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

## Commands

- `:BlinkAI status` shows the active provider, model, and request stats.
- `:BlinkAI toggle` enables or disables the source globally.
- `:BlinkAI provider <name>` switches the active provider at runtime.
- `:BlinkAI model <name>` switches the model for the active provider.
- `:BlinkAI clear` cancels any in-flight request.

## Troubleshooting

- If you see no AI items, confirm `:BlinkAI status` and verify the provider.
- Missing keys will notify once; set `OPENAI_API_KEY` or `providers.openai.api_key`.
- Ensure `curl` is on your PATH and Neovim is 0.10+.
- `timeout_ms` is controlled by blink.cmp under `sources.providers.ai.timeout_ms`.

## License

MIT
