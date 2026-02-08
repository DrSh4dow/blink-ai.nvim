# Release Checklist

## 1. Quality Gates

- [ ] `make format-check`
- [ ] `make lint`
- [ ] `make docs-check`
- [ ] `make test`
- [ ] CI green for all configured Neovim versions.
- [ ] `:checkhealth blink-ai` passes.
- [ ] `:helptags doc` runs without errors.
- [ ] Working tree is clean (`git status` has no pending changes).

## 2. Manual QA Matrix

- [ ] Providers tested:
  - [ ] OpenAI
  - [ ] Anthropic
  - [ ] Ollama
  - [ ] OpenAI-compatible
  - [ ] FIM
- [ ] Filetypes tested:
  - [ ] Lua
  - [ ] TypeScript
  - [ ] Python
  - [ ] Rust
- [ ] Scenarios tested:
  - [ ] Streaming updates in completion menu
  - [ ] Cancellation on new input
  - [ ] Debounce under fast typing
  - [ ] Multi-line insertion ranges
  - [ ] Missing key/error handling UX
  - [ ] Runtime commands (`status`, `toggle`, `provider`, `model`, `clear`, `stats reset`)

## 3. Docs and Metadata

- [ ] `README.md` reflects shipped behavior and defaults.
- [ ] `README.md` install snippet uses the final published repository slug.
- [ ] `doc/blink-ai.txt` mirrors README command/config surface.
- [ ] `CHANGELOG.md` updated with release notes.
- [ ] `CHANGELOG.md` contains a versioned release section (`[X.Y.Z] - YYYY-MM-DD`).
- [ ] `SECURITY.md` and `CONTRIBUTING.md` reviewed.

## 4. Publish

- [ ] Create release tag (`vX.Y.Z`).
- [ ] Publish GitHub release notes from changelog.
- [ ] Announce known limitations and tested provider matrix.
- [ ] Link release notes to CI run and manual QA matrix results.
