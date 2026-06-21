# Mimer roadmap — best clipboard history for developers

**Strategy: wedge-first hybrid.** Lead with the moat Raycast structurally won't build,
keep the parity features as hygiene so we're never subpar, and don't over-invest in OCR.
Decided 2026-06-21 after a competitive deep-dive on Raycast + a full CEO/design/eng/devex
+ cross-model (Codex) plan review. Benchmark **Maccy** for the share we can actually take;
market privacy loudly (MIT, local, account-free, encrypted).

## The wedge (lead — what makes Mimer the developer's choice)

Raycast's clipboard manager is deliberately generic; that genericness is the opening.

- **Transform engine v2** (extends today's ⌘K transforms — Raycast has no equivalent):
  JWT-decode, JSON ↔ TypeScript/Go type, diff two clips, code-aware paste
  (fenced/comment/re-indent/escape-for-JSON-shell-regex), URL surgery (strip tracking,
  decode query), transform chains, and apply-and-paste **without mutating the clipboard**.
- **Developer-domain awareness:** detect & act on git SHAs, issue keys (`PROJ-123`, `#456`),
  stack-trace `file:line`, and **secret detection/redaction** (`AKIA…`, `sk-…`, `ghp_…`,
  `-----BEGIN … KEY-----`) — replaces low-value email detection.
- **Provable privacy:** encrypt history at rest, zero network, no account, MIT — and say so.
- **Paste-stack + paste-as-plain (`⌥⏎`).**
- **Scoped/regex search:** `type:image`, `app:Terminal`, `/regex/`, `since:1h`.

## Hygiene (ship well, don't over-invest)

Image clips · file clips · type filters · per-item metadata detail view. Enough to not
look broken next to Raycast — done carefully, not as the headline.

## Deferred / optional

- **OCR-searchable images** — low value for a developer ICP (devs copy already-searchable
  text); if built, async/off-main only.
- Email detection (superseded by dev-domain awareness).
- Privacy-respecting opt-in sync (possible later wedge).

## Sequenced PRs (engineering-reviewed)

1. **Concurrency machinery** — background `NSManagedObjectContext` + serial worker queue;
   `ClipItem` as the only actor-crossing type; `-strict-concurrency=complete` warnings in
   Swift 5 mode. **Not** a big-bang Swift 6 language-mode flip (that's a later cleanup).
2. **Encrypt at rest** — owns the **full** at-rest story up front: SQLCipher whole-DB +
   Keychain key **and** per-blob AES-GCM for the future image dir; copy-not-mutate
   migration of the existing text-only store with count-parity verification + no-loss
   retry. Done while the store is small (re-keying MB blobs later is far riskier).
3. **Transform engine v2 + paste-as-plain (`⌥⏎`).**
4. **Developer-domain awareness** (git-SHA / issue / stack-trace / secret detection).
5. **Scoped/regex search + paste-stack** (queue visibly ordered; `⏎` never overloaded).
6. **Image clips** — file-backed, content-addressed `SHA256(raw bytes)`, `CGImageSource`
   thumbnails, lazy full image, **blob cleanup in prune/delete + orphan sweep**,
   main-thread atomic snapshot then off-main hash/thumbnail.
7. **File clips** (security-scoped bookmarks).
8. **Type filters + metadata detail view.**
9. **OCR** (optional/late) — async/off-main, downsample-before-Vision, tri-state, cancel-on-delete.
10. **Swift 6 language-mode flip** (cleanup, once 6–9 are stable).

## Risks to hold

- **Biggest:** encrypted **searchable** history + the external **blob hole** — if image
  files / OCR text / filenames sit in plaintext on disk, the "encrypted at rest" claim is
  false. The encryption PR (#2) must decide DB **and** blob encryption together.
- Core Data + SQLCipher is not officially supported — integrate carefully, test on OS updates.
- `NSBatchDeleteRequest` bypasses object lifecycle → image blob files orphan unless prune/
  delete fetch `assetPath` first and a periodic orphan sweep runs.

## Design invariants (when rich types land)

Protect the **mounted-search-field + fixed-row-height** invariant that makes the palette
fast. `type:` **search syntax, not filter chips.** **Conditional, width-growing detail
pane** (never a permanent split — most clips are text). **Paste-stack only ships if the
queue is visibly ordered and `⏎` is never overloaded** (else cut it). Tiny cached
thumbnail in the existing `KindIcon` slot.

## Shipping discipline

Small, dedicated, reviewed PRs into protected `main` via CI/CD (see `docs/CICD.md`).
**E2E-verify every PR**: DebugBridge + snapshots for state/logic; real keystroke +
`screencapture` E2E when Accessibility + Screen Recording are granted to the host.
