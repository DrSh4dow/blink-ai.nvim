#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/README.md"
vimdoc="${repo_root}/doc/blink-ai.txt"

if [[ ! -f "${readme}" || ! -f "${vimdoc}" ]]; then
  echo "README or vimdoc file missing"
  exit 1
fi

shared_tokens=(
  ":BlinkAI status"
  ":BlinkAI toggle"
  ":BlinkAI provider"
  ":BlinkAI model"
  ":BlinkAI clear"
  ":BlinkAI stats reset"
  "OPENAI_API_KEY"
  "ANTHROPIC_API_KEY"
  "OPENAI_COMPATIBLE_API_KEY"
  "FIM_API_KEY"
  "timeout_ms"
)

for token in "${shared_tokens[@]}"; do
  if ! grep -Fq "${token}" "${readme}"; then
    echo "README missing token: ${token}"
    exit 1
  fi
  if ! grep -Fq "${token}" "${vimdoc}"; then
    echo "vimdoc missing token: ${token}"
    exit 1
  fi
done

echo "Documentation sync check passed."
