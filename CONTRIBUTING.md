# Contributing

Start with an issue describing a reproducible bug or a proposed behavior change. Keep changes focused, especially provider authentication, history semantics and forecasts. Code is MIT licensed; see LICENSE and ASSET_PROVENANCE.md.

## Development checks

```sh
swift test
./build.sh
codesign --verify --deep --strict "dist/AI Quota.app"
git diff --check
```

No live provider accounts are required for the core tests. Do not add real account responses or credentials to fixtures. Use synthetic examples that retain relevant structure. Keep canonical provider/window IDs and persisted history compatible when changing display text.

For UI changes, check English and Chinese, collapsed and expanded cards, narrow/height-limited windows, and restart persistence. For pinning changes, manually check desktop and full-screen transitions. Label automated checks separately from live-account and physical-Mac testing; do not claim unperformed validation.

PRs should state the problem, resulting behavior, checks performed and known limitations. Do not include unrelated formatting/refactors or generated build products. Never upload raw login/debug captures; follow [diagnostic guidance](docs/privacy.md#sharing-diagnostics). Report sensitive vulnerabilities privately as described in SECURITY.md, not public issues.
