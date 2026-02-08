# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Full provider set with async streaming support:
  - `openai`
  - `anthropic`
  - `ollama`
  - `openai_compatible`
  - `fim`
- Runtime provider/model control commands:
  - `:BlinkAI provider <name>`
  - `:BlinkAI model <name>`
  - `:BlinkAI stats reset`
- Optional treesitter context and custom user context hook.
- Per-filetype provider/model overrides.
- Provider fixture unit tests and source integration tests.
- CI workflow with formatting, lint, docs sync, and test checks.
- Manual provider smoke workflow for credential-backed API checks.

### Changed
- Hardened request streaming parser and retry behavior for transient/rate-limit failures.
- Improved completion item metadata and status metrics reporting.
- Expanded README and vimdoc setup/troubleshooting guidance.

### Security
- Added secret-safe local env guidance and ignore rules for `.env` files.
