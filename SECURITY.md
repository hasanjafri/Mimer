# Security Policy

Mimer handles clipboard contents (which can include passwords, tokens, and other
secrets), runs non-sandboxed, and posts synthetic keystrokes for auto-paste, so
security reports are taken seriously.

## Reporting a vulnerability

**Please do not open a public issue for security problems.** Instead, report privately
via GitHub's [private vulnerability reporting](https://github.com/hasanjafri/Mimer/security/advisories/new)
(Security → Report a vulnerability), or email the maintainer listed on the GitHub profile.

Include: what you found, how to reproduce it, the affected version, and the impact you see.
You'll get an acknowledgement, and a fix or mitigation plan once it's confirmed.

## Supported versions

Mimer auto-updates via Sparkle, so fixes ship to the **latest** release. Please be on the
newest version before reporting. Only the latest release is supported.

## What Mimer already does

- **History is encrypted at rest** (AES-GCM; the 256-bit key lives in the macOS Keychain,
  this-device-only, never iCloud-synced). Image blobs are encrypted and content-addressed.
- **Secrets are kept out of history** via the `org.nspasteboard.ConcealedType` marker plus a
  password-manager bundle blocklist. Per-app exclusions are **best-effort** (pasteboard changes
  can't always be attributed to the app that made them).
- **No telemetry, no network egress** except the signed Sparkle update check.
- Auto-paste re-verifies the target app before posting ⌘V; updates are EdDSA-signed.

If you find a gap in any of these, that's exactly the kind of report we want.
