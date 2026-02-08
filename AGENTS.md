# AGENTS.md

## Repository Context
- This repo is for `blink-ai.nvim`, a Neovim plugin that injects AI completions into the `blink.cmp` menu.
- The product goals are in `blink-ai-prd.md`; treat it as the source of truth until code exists.
- Design intent: provider-agnostic, async by default, streaming updates, minimal dependencies, hackable Lua.

## Rules From Other Tools
- No Cursor rules found (`.cursor/rules/`, `.cursorrules`).
- No Copilot instructions found (`.github/copilot-instructions.md`).

## Automation + Workflow
- ALWAYS USE PARALLEL TOOLS WHEN APPLICABLE.
- Prefer automation: execute requested actions without confirmation unless blocked by missing info or safety/irreversibility.
- Do not assume a default branch; inspect with `git branch -a` and `git remote show origin` if a remote exists.
- Keep diffs minimal and focused; do not reformat unrelated files.
- When in doubt, follow existing patterns in the codebase once code exists.

## Build / Lint / Test
Current status: tooling is present in this repo.

Available tooling:
- `Makefile`
- `stylua.toml`
- `.luacheckrc`
- `tests/` (plenary.busted)
- `.github/workflows/ci.yml`

Preferred modern defaults (add tooling if missing):
- Formatter: `stylua`.
- Linter: `luacheck` (configurable to allow Neovim globals).
- Tests: `plenary.busted` or `mini.test` (both run headless in Neovim).

Exact commands:
- Format all: `make format` or `stylua lua doc tests`.
- Lint all: `make lint` or `luacheck lua tests`.
- Run tests (plenary): `make test` or `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }" -c "qa"`.

Single-test guidance (only if configured):
- Plenary single file: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/unit/request_spec.lua" -c "qa"`.
- Plenary filter: add `--filter` in the test runner invocation.
- mini.test single file: `nvim --headless -u tests/minimal_init.lua -c "lua require('mini.test').run({dir = 'tests', filter = 'foo'})" -c "qa"`.

## Code Style Guide (Lua / Neovim)
General principles:
- Keep the plugin minimal and provider-agnostic; avoid new hard dependencies.
- Async first: never block the editor; prefer `vim.system` and callbacks.
- Streaming should update completion items incrementally; avoid buffering the whole response.
- Make behavior debounced and cancellable; cancel in-flight requests on new input.
- Favor clear, small modules over a single large file.

Project structure (from PRD; keep consistent):
- `lua/blink-ai/init.lua` for the blink.cmp source entry points.
- `lua/blink-ai/providers/*.lua` for provider implementations.
- `lua/blink-ai/context.lua`, `prompt.lua`, `request.lua`, `transform.lua`, `util.lua` for core logic.
- `doc/blink-ai.txt` and `README.md` for user-facing docs.

Imports / requires:
- Use explicit, local requires at top-level: `local util = require('blink-ai.util')`.
- Do not use dynamic require paths; keep module names stable.
- Avoid circular dependencies; extract shared helpers into `util.lua` or a small module.

Formatting:
- Follow existing formatting in the file.
- If no formatter config exists, use Stylua defaults (spaces, 2-space indent, trailing commas ok).
- Keep lines reasonably short; wrap long tables for readability.

Types and annotations:
- Use EmmyLua annotations for public or tricky interfaces (`---@class`, `---@param`, `---@return`).
- Prefer type inference; only annotate when it aids readability or tooling.

Naming conventions:
- Modules: lower_snake in filenames, `local M = {}` export pattern.
- Functions and locals: short, descriptive, `snake_case`.
- Configuration keys: `snake_case` (align with PRD examples).
- Avoid single-letter names unless used as loop indices in tiny scopes.

Configuration patterns:
- Provide defaults and merge with user options using `vim.tbl_deep_extend('force', defaults, opts)`.
- Keep provider-specific config under `providers.<name>`.
- Read secrets from env vars when available; never log raw API keys.

Error handling and logging:
- Prefer returning empty completion sets over throwing errors.
- Use `vim.notify` with clear, user-facing messages when `notify_on_error` is true.
- Avoid noisy logs; rate-limit or “notify once” for repeated failures.
- Include context in errors (provider name, endpoint), but redact secrets.

Completion behavior:
- Implement blink.cmp source contract: `new`, `enabled`, `get_trigger_characters`, `get_completions`, `resolve`.
- Map responses to `lsp.CompletionItem` with a stable `data.source = 'blink-ai'`.
- Ensure `textEdit` ranges are correct for multiline completions.
- Keep `documentation` readable and avoid markdown fences in AI output.

HTTP and streaming:
- Prefer `vim.system` when available; if `plenary` is used, keep it optional.
- Parse SSE incrementally and call `on_chunk` as data arrives.
- Always return a cancel function from provider `complete`.

Performance:
- Debounce requests (default 300ms per PRD).
- Avoid heavy Tree-sitter work on every keystroke; cache minimal context if needed.
- Respect timeouts; never block completion UI.

Testing guidance (align with PRD):
- Favor real parsing/mapping tests over mocks.
- Test provider response parsing, prompt construction, context extraction, and item mapping.
- For integration tests, mock HTTP at the request layer rather than reimplementing logic.

Docs and UX:
- Update `README.md` and `doc/blink-ai.txt` when behavior or config changes.
- Keep examples concise and aligned with PRD defaults.

Security and privacy:
- Never persist prompts or completions unless explicitly requested.
- Keep telemetry opt-in only and local by default.
- Redact secrets in logs and error messages.

## PRD Alignment Checklist
- Provider-agnostic interfaces remain stable and minimal.
- Streaming and async behavior preserved.
- Debounce + cancellation enforced.
- Minimal dependencies; no heavy frameworks.
- Clear, hackable Lua codebase.

## When You Add Tooling
- Update this file with exact build/lint/test commands.
- Document “single test” commands for the chosen runner.
- Add formatter/linter configs (`stylua.toml`, `.luacheckrc`) if used.
