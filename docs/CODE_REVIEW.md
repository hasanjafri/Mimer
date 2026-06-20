# Code Review — v1 hardening pass

Five independent reviewers audited the codebase (concurrency/Core Data, capture/paste,
palette/focus, feature logic, privacy/release-safety), reading the source directly.

**Verdict — foundation is sound:** `DebugBridge` is provably excluded from Release (whole
file + call site are `#if DEBUG`; Release doesn't define `DEBUG`), **zero network/telemetry**,
concealed/transient pasteboard types honored, snippet↔history separation provably correct, the
changeCount torn-read guard is correct, and no retain cycles.

## Fixed

| Area | Commit | What |
|------|--------|------|
| Palette | `db0c11a` | `⌘⌫` delete (plain `⌫` was ambiguous); selection follows the clip after a `⌘D` reorder; transformed results recorded to history; focus re-asserted across search↔transform modes |
| Capture/paste | `230441a` | `.common` timer mode (no stall while dragging the palette / menu open); `isDismissing` held through the async paste; terminated previous-app guard; panel delegate cleanup; `cancelOperation` routed through the controller; `CGEventSource(.privateState)` so a held ⇧ can't turn ⌘V into ⇧⌘V |
| Classify/transform | `f4463bd` | Title Case no longer mangles `iPhone`/`don't`; base64-decode gated to base64-shaped input (not offered on `test`); code heuristic needs corroboration (`Hi {name}` ≠ code, JSON still is); link needs a real scheme; +3 tests |
| Store/settings | `3db892e` | `save()` logs + rolls back on failure; prefs clamped on load; launch-at-login toggle reconciles the real `SMAppService` status; expanded password-manager blocklist |
| Missing-for-v1 | `bb29215` | Clear History (keeps favorites + snippets) + About pane |
| Release-safety | `cb87baf` | `Mimer.entitlements` (sandbox off) wired under hardened runtime; `release.sh` verifies the signature, validates the staple, warns on multiple identities |

## Deferred (with reason)

- **Swift 6 / full `@MainActor` migration** — the capture path is main-thread-safe today (timer on `RunLoop.main`); pinning the type system is a larger migration, low risk now.
- **Encrypt history at rest** — documented the local-unencrypted tradeoff in Privacy settings + README instead (standard for clipboard managers); revisit on demand.
- **Bare-domain link detection** (`github.com/x` without a scheme) — conservative by design to avoid false positives; scheme + `www.` links are covered.
- **Rapid-copy coalescing** — inherent to changeCount polling (matches Maccy); a documented limitation.

## Outstanding before the first release

- **App icon** — none exists yet (the build references `AppIcon`); needs a design decision.
- **Version number** — `project.yml` default is `0.1.0`; `release.sh <version>` sets the real version per build.
