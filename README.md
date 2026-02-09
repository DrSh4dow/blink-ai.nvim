# blink-ai.nvim

`blink-ai.nvim` is a Neovim plugin that injects AI completions into the `blink.cmp` menu.

## Requirements

- Neovim 0.10+
- `curl`
- `saghen/blink.cmp`

## Compatibility Matrix

| Component | Supported | CI Tested |
|---|---|---|
| Neovim | 0.10+ | `stable`, `v0.10.4` |
| blink.cmp | required | yes |
| OpenAI | yes | parser/integration + optional smoke |
| Anthropic | yes | parser/integration + optional smoke |
| Ollama | yes | parser/integration |
| OpenAI-compatible | yes | parser/integration |
| FIM | yes | parser/integration |

## Install (lazy.nvim)

```lua
{
  "drsh4dow/blink-ai.nvim",
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
  performance_profile = "fast", -- fast, balanced, quality
  provider_overrides = {
    lua = { model = "gpt-4o-mini" },
    markdown = { provider = "ollama", model = "qwen2.5-coder:7b" },
  },
  debounce_ms = 80, -- overridden by profile only when omitted
  max_tokens = 96, -- overridden by profile only when omitted
  n_completions = 1,
  suggestion_mode = "raw", -- raw or paired
  context = {
    before_cursor_lines = 20,
    after_cursor_lines = 8,
    enable_treesitter = false,
    user_context = nil, -- fun(ctx) -> string|nil
    repo = {
      enabled = true,
      max_files = 3,
      max_lines_per_file = 80,
      max_chars_total = 6000,
      include_current_dir = true,
    },
  },
  stats = {
    enabled = false, -- collect request counters for :BlinkAI status
  },
  ui = {
    loading_placeholder = {
      enabled = true, -- show "AI (thinking...)" while request is active
      watchdog_ms = 1200, -- auto-clear placeholder if request stalls
    },
  },
  filetypes = {},
  filetypes_exclude = { "TelescopePrompt", "NvimTree", "neo-tree", "oil" },
  notify_on_error = true,
  providers = {
    openai = {
      api_key = nil, -- defaults to $BLINK_OPENAI_API_KEY
      model = "gpt-4o-mini",
      fast_model = "gpt-5-mini", -- used when model_strategy = "fast_for_completion"
      model_strategy = "fast_for_completion", -- or "respect_model"
      endpoint = "https://api.openai.com/v1/responses",
      headers = {},
      extra_body = {},
    },
    anthropic = {
      api_key = nil, -- defaults to $BLINK_ANTHROPIC_API_KEY
      model = "claude-sonnet-4-20250514",
      endpoint = "https://api.anthropic.com/v1/messages",
      temperature = 0.1,
      headers = {},
      extra_body = {},
    },
    ollama = {
      model = "qwen2.5-coder:7b",
      endpoint = "http://localhost:11434/v1/chat/completions",
      stream_mode = "jsonl", -- jsonl or sse
      headers = {},
      extra_body = {},
    },
    openai_compatible = {
      api_key = nil, -- defaults to $BLINK_OPENAI_COMPATIBLE_API_KEY
      model = "",
      endpoint = "",
      temperature = 0.1,
      headers = {},
      extra_body = {},
    },
    fim = {
      api_key = nil, -- defaults to $BLINK_FIM_API_KEY
      model = "",
      endpoint = "",
      fim_tokens = {
        prefix = "<prefix>",
        suffix = "<suffix>",
        middle = "<middle>",
      },
      stream_mode = "jsonl", -- jsonl or sse
      headers = {},
      extra_body = {},
    },
  },
  system_prompt = nil, -- string or fun(ctx) -> string
  transform_items = nil, -- fun(items) -> items
})
```

## Environment Variables

The plugin uses its own prefixed environment variables to avoid consuming global credentials:

- `BLINK_OPENAI_API_KEY`
- `BLINK_ANTHROPIC_API_KEY`
- `BLINK_OPENAI_COMPATIBLE_API_KEY`
- `BLINK_FIM_API_KEY`

Global provider variables (for example `OPENAI_API_KEY`) are intentionally ignored by default.

## Suggestion Shaping

- `raw` (default): returns provider candidates as-is.
- `paired`: emits at most 2 items per request:
  - item 1: compact single-line suggestion
  - item 2: full-form suggestion (multiline when available)
- While a request is in flight, blink-ai emits a single `AI (thinking...)` placeholder item.
- If a request stalls, the placeholder is automatically cleared after `ui.loading_placeholder.watchdog_ms`.
- Streamed provider chunks are buffered internally and the completion menu is updated with the final AI result.
- AI items use a bot icon (`󰚩`) in blink.cmp.

## Providers

- `openai`: Responses API, streaming SSE.
- `anthropic`: messages API, streaming SSE.
- `ollama`: local inference (`/v1/chat/completions`, `/api/chat`, or `/api/generate`).
- `openai_compatible`: generic OpenAI-style chat endpoints.
- `fim`: generic FIM-style endpoints with configurable FIM tokens.

## Commands

- `:BlinkAI status` show provider, configured/effective model, and runtime status.
- `:BlinkAI toggle` enable/disable the source globally.
- `:BlinkAI provider <name>` switch active provider.
- `:BlinkAI model <name>` switch model for the active provider.
- `:BlinkAI clear` cancel in-flight request.
- `:BlinkAI stats status` show metrics (same as status).
- `:BlinkAI stats reset` reset counters and last error.

## Testing and Tooling

- Format: `make format`
- Format check: `make format-check`
- Lint: `make lint`
- Docs sync: `make docs-check`
- Tests: `make test`
- Full local quality gate: `make test-all`
- Optional credential-backed smoke check: `make smoke`

## Release Quality Process

- Use `RELEASE_CHECKLIST.md` for final release gates.
- Keep `CHANGELOG.md` updated for every release.
- Follow contribution guidelines in `CONTRIBUTING.md`.
- Security process and disclosure guidance are in `SECURITY.md`.

## Troubleshooting

- Missing API key:
  - OpenAI: `BLINK_OPENAI_API_KEY`
  - Anthropic: `BLINK_ANTHROPIC_API_KEY`
  - OpenAI-compatible: `BLINK_OPENAI_COMPATIBLE_API_KEY`
  - FIM: `BLINK_FIM_API_KEY`
- Check `:BlinkAI status` for last error and in-flight state.
- Run `:checkhealth blink-ai` for environment and provider configuration checks.
- Ensure `curl` is available and endpoint URLs are reachable.
- If OpenAI models like `gpt-5.2-codex` return 400, ensure `providers.openai.temperature` is unset unless your model supports it.
- If OpenAI models return 404, verify provider is `openai` and endpoint is `/v1/responses`.
- If completions do not appear, verify blink source config includes `module = "blink-ai"`.
- If `AI (thinking...)` appears too briefly or too long, tune `ui.loading_placeholder.watchdog_ms`.
- If requests are too frequent, increase `debounce_ms`.
- If completions time out, increase `sources.providers.ai.timeout_ms` in blink.cmp config.

## Known Limitations

- Network/provider availability and account quotas can still cause transient failures.
- Different OpenAI-compatible/FIM endpoints may require provider-specific body fields via `extra_body`.
- Provider smoke checks require API credentials and are intended for manual or workflow-dispatch runs.

## License

MIT
