# Contributing

## Development Setup

1. Clone the repository.
2. Ensure dependencies are installed:
   - Neovim 0.10+
   - `curl`
   - `stylua`
   - `luacheck`
3. Install plenary locally for tests:
   - `mkdir -p .tests`
   - `git clone --depth=1 https://github.com/nvim-lua/plenary.nvim .tests/plenary.nvim`

## Local Commands

- Format:
  - `make format`
- Format check:
  - `make format-check`
- Lint:
  - `make lint`
- Docs sync check:
  - `make docs-check`
- Tests:
  - `make test`
- Full local gate:
  - `make test-all`

## Provider Smoke Tests (Optional)

1. Put credentials in `.env` (never commit it).
   - `BLINK_OPENAI_API_KEY=...`
   - `BLINK_ANTHROPIC_API_KEY=...`
2. Load env vars:
   - `set -a; source .env; set +a`
3. Run smoke check:
   - `make smoke`

## Code Guidelines

- Keep dependencies minimal.
- Preserve async + streaming behavior.
- Prefer small focused modules over broad refactors.
- Avoid logging secrets in notifications or errors.
- Add tests for parsing, mapping, and edge-case behavior.

## Pull Request Expectations

- Include tests for behavior changes.
- Keep docs (`README.md`, `doc/blink-ai.txt`) in sync.
- Ensure `make test-all` passes before review.
- Describe provider-specific assumptions when changing payload parsing.
