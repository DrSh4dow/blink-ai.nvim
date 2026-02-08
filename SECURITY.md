# Security Policy

## Supported Versions

Only the latest release branch is considered supported for security updates.

## Reporting a Vulnerability

Please do not open public issues for sensitive security findings.

Instead, contact the maintainer privately with:
- impact summary,
- reproduction details,
- affected versions,
- suggested mitigation (if available).

You can expect:
- acknowledgement within 7 days,
- triage and severity assessment,
- coordinated disclosure once a fix is available.

## Secrets and Privacy

- Do not commit API credentials.
- `.env` and `.env.*` files are intentionally ignored.
- The plugin does not persist prompts/completions by default.
- Error messages should never include raw API keys.
