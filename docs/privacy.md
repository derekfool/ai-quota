# Local data and privacy

AI Quota reads subscription usage. It has no app-authored analytics, advertising, cloud-sync, or quota-export backend. This does not make it offline: embedded official pages and the locally installed Codex subprocess communicate with their providers under those providers' policies.

## Stored data

- `~/Library/Application Support/AIQuota/quota-cache.json`: last quota snapshots and timestamps. On startup, cached values await validation; failures keep them visibly stale.
- `~/Library/Application Support/AIQuota/quota-history.json`: sampled usage and cycle metadata used for history and forecasts. It survives restart. Recent samples are dense; older current-cycle samples are reduced. This is separate from the cache.
- macOS UserDefaults domain `com.derektan.ai-quota`: language, card order/collapse state, pin/visibility/position, sounds, watch duration, selected Claude workspace and optional Codex executable path.
- Persistent WebKit website data: provider sign-in sessions. The app uses the default WebKit store; it does not import Chrome cookies or ask you to paste tokens. App code does not read passwords or export cookies. WebKit manages site storage.
- Codex authentication remains with your Codex installation, not these JSON files.

## Removing data

Quit AI Quota before moving or removing its cache/history files. In Finder, use Go → Go to Folder and enter `~/Library/Application Support/AIQuota`. Back up the two JSON files if you want to restore history; removing them clears the local baseline and cannot recover past observations from the providers.

Deleting cache/history does **not** sign out websites or clear preferences. This version has no app-level disconnect / clear-WebKit-data button. Exact WebKit filesystem deletion instructions are deliberately not provided without platform validation. Use the provider's sign-out/account session controls; do not assume signing out in Chrome clears this app's session. Provider-specific sign-out flows still need acceptance testing.

History currently assumes continued use of one account per provider. Claude workspace selection clears its history, but there is no universal account identity guard across all providers. Avoid mixing accounts when interpreting trends.

## Sharing diagnostics

Prefer the provider name, macOS version, app commit, visible error text and reproduction steps. Remove names, email addresses, workspace identifiers, billing details and quota values you do not want public. Never share cookies, auth headers, tokens, WebKit storage, Codex authentication files, or complete cache/history files. The optional `--check-codex` command prints real account quota JSON; it is not a safe-to-share diagnostic bundle.
