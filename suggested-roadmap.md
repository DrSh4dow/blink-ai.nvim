# Suggested Roadmap

## Overall Objective
Deliver a minimal, provider-agnostic, streaming-first blink.cmp source that is
stable, auditable, and fast enough for daily use, with clear docs and tests.

## Next Steps

### v0.1.x Hardening
- Finish OpenAI provider edge cases (rate-limit handling, malformed JSON fallbacks).
- Validate textEdit ranges against blink.cmp ctx across multiple filetypes.
- Add lightweight metrics in :BlinkAI status (request count, last duration, last error).
- Expand docs with a troubleshooting checklist and provider config examples.

### v0.2.0 Multi-Provider
- Implement Anthropic (Messages API) streaming.
- Implement Ollama (local) streaming.
- Implement OpenAI-compatible provider.
- Implement FIM provider with configurable FIM tokens.
- Normalize provider responses to a shared streaming interface.

### v0.3.0 Polish + CI
- Optional treesitter context extraction (guarded, low cost).
- Add transform_items hook examples and per-filetype overrides.
- Add stylua + luacheck configs and a basic CI workflow.
- Publish vimdoc tags and ensure README mirrors vimdoc.

### v0.4.0 Advanced
- Multi-candidate completions beyond OpenAI `n` with stable sorting.
- Context hook for user RAG integrations.
- Optional local-only usage stats (opt-in).

## Functional Tests

### Manual QA Matrix
- Providers: OpenAI, Anthropic, Ollama, OpenAI-compatible, FIM.
- Filetypes: Lua, TypeScript, Python, Rust.
- Scenarios:
  - Normal typing with streaming updates in menu.
  - Cancellation on new keystrokes.
  - Debounce behavior under fast typing.
  - Multi-line completion insertion.
  - Missing API key and network failure messaging.
  - :BlinkAI status/toggle/provider/model/clear commands.

### Automated Tests (Recommended)
- Unit tests:
  - SSE parsing (partial frames, multi-line data, [DONE]).
  - Prompt construction (chat + FIM).
  - Completion mapping (range inference, labels, documentation).
- Integration tests:
  - Mock HTTP streaming responses to verify incremental callback behavior.
  - End-to-end flow from get_completions -> callback -> items.

## Release Criteria
- All providers implemented with streaming and cancellation.
- No crashes on malformed responses; errors are user-friendly and rate-limited.
- Functional tests green; manual QA matrix completed.
- Docs match behavior and configuration defaults.
