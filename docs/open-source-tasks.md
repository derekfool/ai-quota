# Open-source preparation status

Updated 2026-09-13. Source publication and downloadable releases are separate milestones. The repository remains private until the owner explicitly authorizes visibility changes.

## Implemented locally, pending delivery / CI run

- English README and Chinese counterpart with four-provider onboarding and current global monitoring behavior.
- Cache/history/preferences/WebKit data handling, diagnostic redaction and account-switch limits.
- Known limitations, including the deferred pinned-Space black flash.
- Contribution guide, bug-report and pull-request templates.
- Read-only GitHub Actions build/test/bundle checks and pinned Gitleaks scan; no account secrets or release upload step.
- Defensive ignore rules for credentials, signing files and local account data.

## Owner decisions

- MIT selected; LICENSE added with Derek Tan as copyright holder.
- Owner states sounds and icon/reference imagery were generated with ChatGPT; recorded in ASSET_PROVENANCE.md.
- Owner requires sanitization. Current personal Cursor examples replaced with synthetic fixtures; owner selected a separate clean initial commit, preserving the old private repository.
- GitHub Private Vulnerability Reporting selected; enabling requires the public repository. SECURITY.md states the pending status.

## Verified locally

- 62 XCTest cases pass after replacing personal Cursor fixtures with synthetic values.
- actionlint 1.7.12 accepts the workflow; YAML parses.
- Gitleaks 8.30.1 scans all 12 existing commits and the proposed working files with redacted output: no findings. This does not sanitize author metadata or prove absence of every secret.
- Git diff whitespace checks pass. The latest application build was already verified at 8b420e9; this preparation changes documentation, CI and fixtures, not application code.

## Remaining acceptance / publication work

- Run CI on GitHub after delivery and resolve failures; local checks alone are insufficient.
- Verify the private-reporting route before linking it as available.
- Complete provider sign-out / data-removal acceptance; current limitation is documented.
- Owner explicitly approves making source public after unresolved decisions are handled.
- Optional binary release: Developer ID credentials, notarization, supported architectures and independent clean-Mac installation. No signed-download promise yet.

The older [readiness review](open-source-readiness.md) is a dated audit snapshot; this list tracks subsequent preparation.
