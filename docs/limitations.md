# Compatibility and known limitations

- Deployment target: macOS 13+. Locally tested on Apple Silicon; minimum-version and Intel acceptance remain pending. CI does not validate physical trackpad gestures or account login.
- Codex uses the installed App Server protocol. Cursor/Claude use website endpoints; Gemini uses an observed official-page RPC response. These can change without notice and are not guarantees of vendor API support.
- Returned pools vary by plan. Missing reset metadata prevents a reliable forecast; white is unknown, not necessarily plentiful quota.
- Usage can be delayed upstream. Polling every 10 seconds does not guarantee ten-second accounting.
- History begins with observed data. Offline endpoints may contribute a known same-cycle difference, while charts leave gaps. No full historical backfill is available.
- WebKit sign-in can require provider verification. Chrome sessions are separate. Dedicated disconnect/data-clearing UI is not implemented.
- A pinned window may briefly show a black backdrop during a macOS Space/full-screen transition. The owner has deferred this cosmetic issue; a display-flush workaround did not resolve it and was removed. Unpinned windows remain in their own Space.
- App bundles are locally ad-hoc signed. Notarization, clean-Mac installation and a public downloadable release are separate pending work.
