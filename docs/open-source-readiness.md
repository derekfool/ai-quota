# Open-source readiness review

Reviewed 2026-09-12. Repository: `derekfool/ai-quota`, base `c5f2268`, plus the current uncommitted Chinese/English implementation. This is a readiness review, not a penetration test or legal clearance. No repository visibility, licensing, release, signing identity, or Git history was changed.

## Conclusion

The local bilingual app is ready for owner review. Before announcing an open-source project, resolve licensing/resource provenance and decide whether the existing history may be public, then correct the onboarding/privacy documentation. Downloadable app distribution has separate signing and clean-machine acceptance work.

## Findings

### R1 — Before source publication: license and asset provenance are missing

The repository has no LICENSE; GitHub reports `license: null`. Package.swift declares no external package dependencies, but five WAV files are bundled and there is no asset-provenance/license notice. The conversation described original synthesis; the repository alone does not document the generation source or grant for each WAV. SF Symbols are used through system image names, not bundled brand artwork.

Action: owner chooses a source license, records the origin and redistribution terms of the five audio assets, and adds any necessary third-party notices. Do not invent ownership or license grants. Public visibility alone does not establish an open-source license. [GitHub licensing guidance](https://docs.github.com/en/enterprise-cloud%40latest/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).

Evidence: root file inventory, Package.swift, Sources/QuotaCore/Sounds, GitHub repository metadata.

### R2 — Before source publication: decide what historical personal information may be public

The 11 reachable local commits contain one non-noreply author email. docs/design.md:31 explicitly describes real Cursor usage and a billing date. No credential was identified there, but these are personal metadata. The historical versions remain available even if the latest document is edited.

Action: owner accepts publication of these details, or authorizes a separate sanitization/history strategy before making the repository public. No history rewrite or deletion was performed. A new clean public repository is another decision, not an automatic action.

Evidence: author-email category counts only; docs/design.md:31; all-ref history scan. This report intentionally does not reproduce the email or usage values.

### R3 — Before announcement: README onboarding and privacy claims are stale

README.md:14 still describes two independent monitoring switches; the app now has one global switch for four providers. README.md:38 says only quota snapshots are cached, but QuotaStore also writes quota-history.json. The new language section is bilingual, while the main installation and usage guide is still Chinese. The opening usage flow refers to dist/AI Quota.app, but dist is ignored and GitHub has no release assets. GitHub's description still mentions only Codex and Cursor.

Action: write consistent English/Chinese onboarding, put source build instructions before opening the generated app, explain four providers and current monitoring behavior, and describe history, cache, preferences, WebKit sign-in persistence and deletion. Include a safe diagnostic-sharing policy. The opt-in --check-codex mode prints real quota JSON; users should not be encouraged to post its output without review.

Evidence: README.md:3–38; QuotaStore.swift:115–118, 284–308; AIQuotaApp.swift:20–27; .gitignore; GitHub metadata/releases.

### R4 — Before distributing downloads: signed release and installation validation are missing

build.sh:10 creates an ad-hoc signature. There are no GitHub releases. Current verification is a local Apple Silicon build, not a clean-machine Gatekeeper installation test, Intel test, or macOS 13 acceptance test. No Developer ID/notarization pipeline was found.

Action: for binary distribution, prepare a versioned signed/notarized artifact, verify embedded resources and checksums, and test on a separate clean Mac. Explicitly state supported architectures and tested OS versions. This is separate from publishing source code. [Apple Developer ID guidance](https://developer.apple.com/developer-id/) and [distribution testing guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

### R5 — Before accepting outside contributions: CI and reporting guidance are missing

GitHub reports zero Actions workflows. No CONTRIBUTING, SECURITY, issue templates, or PR template were found. 62 tests passed locally, but there is no automated contributor check or documented private security-reporting route.

Action: add macOS build/test CI, a concise contribution guide, redacted issue-report fields, and an owner-selected security contact. Include repeatable language-switch and first-run checks. No email/contact was invented.

### R6 — Before broad rollout: provider compatibility and sign-in cleanup need a clear contract

Cursor and Claude use same-origin website endpoints. Gemini observes a specific batchexecute RPC (`jSf9Qc`) and positional response fields, with the official usage page forced to English. These are compatibility adapters, not evidence of vendor-supported public APIs. All three use default persistent WebKit stores. No app-level disconnect/clear-sign-in action was found.

Action: document supported subscriptions, tested client/web versions, missing-reset behavior, update expectations and known login limitations. Provide a supported sign-out/data-clearing route or exact tested instructions. Do not claim legal/vendor approval from endpoint functionality. Verify platform requirements before broader distribution.

Evidence: CursorClient.swift:9, 53–54; ClaudeClient.swift:74–86; GeminiClient.swift:11–18; GeminiWebCapture.swift:6–24.

### R7 — Before public history grows: defensive secret hygiene

.gitignore only covers .build, dist and .DS_Store. The inspected history has no tracked credential/cache/history files, but nothing explicitly excludes future local .env files, exported sessions, signing certificates or diagnostic captures.

Action: extend ignore rules for local sensitive artifacts, add a maintained secret scanner in CI, and review findings rather than treating a passing regex as a security guarantee.

## Verified evidence and limits

- GitHub readback: private repository, default main, no license, no releases, zero Actions workflows. Visibility was not changed.
- Inspected all 11 reachable local commits and 123 unique UTF-8 text blobs for private-key headers, common GitHub/OpenAI/AWS token formats, JWTs and credential assignments. No pattern hits; no sensitive credential/cache/history filenames or personal home-directory paths found. These heuristics can miss unknown formats, split/encoded secrets, unreachable objects and external content. No maintained scanner was installed; GitHub secret-scanning alerts/settings were not assessed.
- Five current WAV assets contain only fmt/data chunks. No embedded text metadata was found. This does not establish audio ownership or licensing and does not analyze spoken content.
- Application source review found same-origin usage reads, a Gemini observer limited to the official origin/RPC, WebKit-owned login storage, and no app-authored analytics/export backend. This is static evidence; official pages and the Codex subprocess still communicate with their services. No network penetration test was performed.
- Bilingual implementation: 62 XCTest cases pass; Release build and installed signature check pass. Actual UI tested in English, including menus and expanded trend; switched to Chinese without losing the expanded chart, then restarted and confirmed saved Chinese selection. Provider websites/system-generated errors follow their own language settings. Full VoiceOver, Intel/macOS 13, and clean-account onboarding were not tested.
- Parser IDs, persisted quota titles, and history schema are unchanged by localization. No source-publication/release claim follows from successful local testing.

## Suggested order

1. Owner decisions: license, audio provenance, historical personal metadata.
2. English/Chinese README and truthful privacy/onboarding documentation.
3. CI, secret hygiene, contribution/security reporting.
4. Optional downloadable release: Developer ID/notarization and clean-Mac acceptance.
5. Explicit owner instruction to publish, then verify visibility and released artifacts.
