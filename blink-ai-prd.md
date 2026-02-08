# blink-ai.nvim — Product Requirements Document

**Version:** 0.1.0  
**Status:** Draft  
**Author:** Daniel  
**Date:** February 2026

---

## 1. Overview

**blink-ai.nvim** is a Neovim plugin that provides AI-powered code completions as a native blink.cmp source. Unlike copilot.lua (inline ghost text) or chat-based plugins (side panels), blink-ai.nvim injects AI suggestions directly into the blink.cmp completion menu alongside LSP, snippets, and buffer completions.

Users can connect any AI model — cloud or local — through a unified provider interface.

---

## 2. Problem Statement

Current AI completion options in Neovim fall into three categories:

1. **Inline ghost text** (copilot.lua, Supermaven) — conflicts with the completion menu, requires separate keybindings, and can't be mixed/ranked with LSP results.
2. **Chat panels** (ChatGPT.nvim, gp.nvim) — require context switching, not inline completions.
3. **minuet-ai.nvim** — closest to what we want, but it's a large plugin that bundles its own prompt engineering, virtual text mode, LSP server mode, and multiple frontends. It uses `plenary.nvim` for HTTP (curl-based) and has a complex configuration surface.

**blink-ai.nvim** aims to be a focused, minimal, blink-cmp-first source that does one thing well: get AI completions into the blink.cmp menu.

---

## 3. Goals & Non-Goals

### Goals
- Native blink.cmp source with zero friction setup
- Provider-agnostic: OpenAI, Anthropic, Ollama, any OpenAI-compatible API, and FIM endpoints
- Streaming support: items appear in the menu as they arrive
- Async by default: never block the editor
- Debounced requests to avoid hammering APIs on every keystroke
- Multi-line completion support with proper textEdit ranges
- Context-aware prompts (surrounding code, filetype, treesitter context)
- Minimal dependencies (only `blink.cmp` required, optional `plenary.nvim` or native `vim.system` for HTTP)
- Clear, hackable Lua codebase

### Non-Goals
- Virtual text / ghost text mode (use copilot.lua for that)
- Chat interface
- Built-in LSP server mode
- Prompt marketplace or template system
- RAG / codebase indexing (can be added via hooks)

---

## 4. Architecture

### 4.1 Directory Structure

```
blink-ai.nvim/
├── lua/
│   └── blink-ai/
│       ├── init.lua              # blink.cmp source entry (new/get_completions/resolve)
│       ├── config.lua            # Configuration schema & defaults
│       ├── context.lua           # Buffer context extraction (before/after cursor, filetype, treesitter)
│       ├── prompt.lua            # Prompt construction (chat & FIM templates)
│       ├── request.lua           # HTTP client abstraction (vim.system / curl)
│       ├── providers/
│       │   ├── init.lua          # Provider registry & base interface
│       │   ├── openai.lua        # OpenAI / OpenAI-compatible (chat completions)
│       │   ├── anthropic.lua     # Anthropic Messages API
│       │   ├── ollama.lua        # Ollama local inference
│       │   └── fim.lua           # FIM endpoint (Codestral, DeepSeek, Qwen)
│       ├── transform.lua         # Response → CompletionItem[] mapping
│       └── util.lua              # Debounce, cancellation, logging
├── doc/
│   └── blink-ai.txt             # Vimdoc
├── README.md
└── LICENSE
```

### 4.2 Data Flow

```
Keystroke → blink.cmp calls get_completions(ctx, callback)
         → Debounce timer (configurable, default 300ms)
         → context.lua extracts surrounding code + metadata
         → prompt.lua builds the provider-specific payload
         → request.lua sends async HTTP request
         → Provider streams/returns response
         → transform.lua maps response → lsp.CompletionItem[]
         → callback({ items, is_incomplete_forward = true })
         → Items appear in blink.cmp menu with [AI] label
```

### 4.3 blink.cmp Source Interface

The plugin implements the blink.cmp source contract:

```lua
--- @class blink.cmp.Source
local source = {}

function source.new(opts, provider_config)
  -- Validate opts, initialize provider, set up debounce
end

function source:enabled()
  -- Check filetype allowlist/blocklist
  -- Check if provider is configured
end

function source:get_trigger_characters()
  return {} -- trigger on normal typing, no special chars
end

function source:get_completions(ctx, callback)
  -- 1. Debounce
  -- 2. Cancel any in-flight request
  -- 3. Extract context
  -- 4. Build prompt
  -- 5. Send async request with streaming callback
  -- 6. On each streamed chunk: callback({ items, is_incomplete_forward = true })
  -- 7. On complete: callback({ items, is_incomplete_forward = false })
  -- Return cancel function
end

function source:resolve(item, callback)
  -- Populate documentation field with the full completion preview
end
```

---

## 5. Provider Interface

Each provider implements:

```lua
--- @class blink_ai.Provider
--- @field name string
--- @field setup fun(opts: table): nil
--- @field complete fun(prompt: blink_ai.Prompt, on_chunk: fun(text: string), on_done: fun(), on_error: fun(err: string)): fun() cancel
```

### 5.1 Supported Providers

| Provider | API Style | Auth | Streaming |
|---|---|---|---|
| `openai` | Chat completions | API key (env var or config) | SSE |
| `anthropic` | Messages API | API key (env var or config) | SSE |
| `ollama` | Chat completions (local) | None | SSE |
| `openai_compatible` | Chat completions | API key (env var or config) | SSE |
| `fim` | FIM endpoint | API key (env var or config) | SSE |

### 5.2 Custom Providers

Users can register custom providers:

```lua
require('blink-ai').register_provider('my-provider', {
  name = 'My Provider',
  setup = function(opts) end,
  complete = function(prompt, on_chunk, on_done, on_error)
    -- Custom implementation
    return function() end -- cancel fn
  end,
})
```

---

## 6. Configuration

```lua
require('blink-ai').setup({
  -- Active provider
  provider = 'openai',

  -- Debounce delay in ms before sending request
  debounce_ms = 300,

  -- Maximum tokens to request from the model
  max_tokens = 256,

  -- Number of completion candidates to request (if supported)
  n_completions = 3,

  -- Context window: lines before/after cursor to include
  context = {
    before_cursor_lines = 50,
    after_cursor_lines = 20,
  },

  -- Filetype allowlist (empty = all filetypes)
  filetypes = {},
  -- Filetype blocklist
  filetypes_exclude = { 'TelescopePrompt', 'NvimTree', 'neo-tree', 'oil' },

  -- Notify on errors
  notify_on_error = true,

  -- Provider-specific options
  providers = {
    openai = {
      api_key = nil, -- defaults to $OPENAI_API_KEY
      model = 'gpt-4o-mini',
      endpoint = 'https://api.openai.com/v1/chat/completions',
      temperature = 0.1,
      extra_body = {}, -- merged into the request body
    },
    anthropic = {
      api_key = nil, -- defaults to $ANTHROPIC_API_KEY
      model = 'claude-sonnet-4-20250514',
      endpoint = 'https://api.anthropic.com/v1/messages',
      temperature = 0.1,
      extra_body = {},
    },
    ollama = {
      model = 'qwen2.5-coder:7b',
      endpoint = 'http://localhost:11434/v1/chat/completions',
      extra_body = {},
    },
    openai_compatible = {
      api_key = nil,
      model = '',
      endpoint = '',
      temperature = 0.1,
      extra_body = {},
    },
    fim = {
      api_key = nil,
      model = '',
      endpoint = '',
      extra_body = {},
    },
  },

  -- System prompt override (string or function(ctx) -> string)
  system_prompt = nil,

  -- Transform items before returning to blink.cmp
  transform_items = nil, -- fun(items: lsp.CompletionItem[]): lsp.CompletionItem[]
})
```

---

## 7. User-Facing Setup (lazy.nvim)

```lua
{
  'drsh4dow/blink-ai.nvim',
  dependencies = { 'saghen/blink.cmp' },
  opts = {
    provider = 'openai',
    providers = {
      openai = {
        model = 'gpt-4o-mini',
      },
    },
  },
  specs = {
    {
      'saghen/blink.cmp',
      optional = true,
      opts = {
        sources = {
          default = { 'lsp', 'path', 'snippets', 'buffer', 'ai' },
          providers = {
            ai = {
              name = 'AI',
              module = 'blink-ai',
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

---

## 8. Prompt Engineering

### 8.1 Chat Mode (OpenAI, Anthropic, Ollama)

Two-message pattern:

- **System message:** Code completion instructions, filetype, expected output format (return only code, no markdown fences, no explanation).
- **User message:** Template with `context_before_cursor` + `<cursor>` marker + `context_after_cursor`.

The prompt requests multiple candidates as a JSON array to map to multiple CompletionItems.

### 8.2 FIM Mode (Codestral, DeepSeek, Qwen)

Standard fill-in-the-middle format:

```
<prefix>{context_before_cursor}</prefix>
<suffix>{context_after_cursor}</suffix>
<middle>
```

Uses the FIM-specific tokens for each model (configurable via `fim_tokens` in provider options).

### 8.3 Context Extraction

- Lines before/after cursor (configurable window)
- Current line with cursor position
- Buffer filetype + filename
- (Optional) Treesitter node at cursor for scope-aware context
- (Future hook) User-provided context function for RAG integration

---

## 9. Completion Item Mapping

Each AI response is mapped to `lsp.CompletionItem`:

| Field | Value |
|---|---|
| `label` | First line of the completion (truncated for menu display) |
| `kind` | Custom `AI` kind (registered via blink.cmp kind extension) |
| `insertTextFormat` | `PlainText` (or `Snippet` if the model returns snippet syntax) |
| `textEdit` | Range from current cursor keyword start to cursor position, `newText` = full completion |
| `documentation` | Full multi-line preview (shown in doc window) |
| `filterText` | Empty string or current keyword (to avoid blink's fuzzy filtering removing AI results) |
| `sortText` | Priority prefix to control ordering among AI items |
| `data.source` | `'blink-ai'` for identification |

---

## 10. Commands

| Command | Description |
|---|---|
| `:BlinkAI status` | Show active provider, model, request stats |
| `:BlinkAI toggle` | Enable/disable the source |
| `:BlinkAI provider <name>` | Switch active provider at runtime |
| `:BlinkAI model <name>` | Switch model for current provider |
| `:BlinkAI clear` | Cancel any in-flight request |

---

## 11. Performance Requirements

- **Debounce:** Configurable, default 300ms. No request fires until the user pauses typing.
- **Cancellation:** Every request is cancellable. New keystrokes cancel in-flight requests.
- **Timeout:** Default 5000ms. blink.cmp's `timeout_ms` serves as the hard cutoff.
- **Memory:** No unbounded caches. Cached responses are evicted on buffer change or cursor movement beyond threshold.
- **Startup:** Zero cost. The source initializes lazily on first `InsertEnter`.

---

## 12. Error Handling

- HTTP errors (4xx, 5xx): Log via `vim.notify` at WARN level (if `notify_on_error` is true), return empty items.
- Malformed responses: Gracefully degrade, log the raw response for debugging.
- Missing API key: Disable the source with a one-time notification.
- Network timeout: Return empty items, no editor freeze.
- Rate limiting (429): Exponential backoff with jitter, surface to user.

---

## 13. Testing Strategy

- **Unit tests:** Provider response parsing, prompt construction, context extraction, item mapping. Use `plenary.busted` or `mini.test`.
- **Integration tests:** Mock HTTP responses, verify full flow from `get_completions` to `callback` with expected `CompletionItem[]`.
- **Manual QA matrix:** Test with OpenAI, Anthropic, Ollama, and at least one FIM provider across Lua, TypeScript, Python, Rust filetypes.

---

## 14. Milestones

### v0.1.0 — MVP
- [ ] blink.cmp source skeleton (new, get_completions, resolve)
- [ ] OpenAI provider with streaming
- [ ] Basic context extraction (lines before/after)
- [ ] Debounce + cancellation
- [ ] Minimal config with sane defaults
- [ ] README with lazy.nvim setup

### v0.2.0 — Multi-Provider
- [ ] Anthropic provider
- [ ] Ollama provider
- [ ] OpenAI-compatible provider
- [ ] FIM provider
- [ ] Runtime provider/model switching commands

### v0.3.0 — Polish
- [ ] Treesitter-aware context
- [ ] Custom provider registration API
- [ ] `transform_items` hook
- [ ] Vimdoc generation
- [ ] CI with linting (stylua, luacheck) + tests

### v0.4.0 — Advanced
- [ ] Multi-candidate support (n_completions > 1)
- [ ] Context hook for RAG integration (user-provided function)
- [ ] Per-filetype provider/model overrides
- [ ] Telemetry-free usage stats (local only, opt-in)

---

## 15. Competitive Comparison

| Feature | blink-ai.nvim | minuet-ai.nvim | blink-cmp-copilot |
|---|---|---|---|
| Completion target | blink.cmp menu only | blink, cmp, virtual text, LSP | blink.cmp menu only |
| Provider support | Any (pluggable) | Built-in set | GitHub Copilot only |
| Dependencies | blink.cmp | plenary.nvim | copilot.lua |
| FIM support | Yes | Yes | No |
| Streaming to menu | Yes | Yes | No |
| Custom providers | Yes (register API) | No | No |
| Prompt customization | System prompt + hooks | Template system | None |
| Codebase size target | < 1000 LOC | ~3000+ LOC | ~200 LOC |

---

## 16. Open Questions

1. **Should we use `vim.system` (Neovim 0.10+) or `plenary.curl` for HTTP?** Leaning toward `vim.system` with curl to avoid the plenary dependency, but need to handle streaming SSE parsing ourselves.
2. **How to handle multi-line completions in the menu?** blink.cmp shows `label` as a single line. Full completion would live in `textEdit.newText` and be previewed via `documentation` or ghost text on selection.
3. **Should we support `n_completions > 1` from day one?** Multiple candidates from a single request are cheap but complicate the UX. Defer to v0.4.0.
4. **filterText strategy:** If we set `filterText = ''`, blink won't fuzzy-filter AI results. If we set it to the keyword, fast typers may see AI results disappear. Need to test both approaches.

---

## 17. References

- [blink.cmp source boilerplate](https://cmp.saghen.dev/development/source-boilerplate)
- [blink.cmp source configuration](https://cmp.saghen.dev/configuration/sources)
- [blink-cmp-copilot](https://github.com/giuxtaposition/blink-cmp-copilot) — reference implementation for a blink source wrapping an external AI
- [minuet-ai.nvim](https://github.com/milanglacier/minuet-ai.nvim) — comprehensive AI completion plugin with blink support
- [LSP CompletionItem spec](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#completionItem)
