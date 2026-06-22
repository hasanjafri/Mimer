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

## Sequenced PRs (engineering-reviewed, wedge-first)

Lead with the wedge (pure-logic, no data-model/concurrency deps); keep encryption before
images; concurrency machinery sits just before the image/OCR work that needs it.

1. **Transform engine v2 + paste-as-plain (`⌥⏎`).** *In progress.* Shipped: developer
   transforms — Decode JWT, Strip tracking params, Decode query string, Unix↔ISO 8601,
   **JSON → TypeScript**, **sort/dedupe/reverse lines**, **camelCase/snake_case** (all pure,
   gated, unit-tested). Next in this bucket: JSON→Go/Swift, diff two clips, transform chains,
   apply-and-paste-without-mutating-clipboard, and paste-as-plain (needs rich types first).
2. **Developer-domain awareness** (git-SHA / issue-key / stack-trace `file:line` /
   secret detection). *In progress.* Shipped: **secret detection** (`SecretDetector`) —
   detected API keys/tokens/PEM/secret-env are **masked** in the list (not skipped: Mimer
   is local/no-cloud and devs re-paste secrets, so the full value is stored + pasted, only
   the display is masked; toggle in Privacy). Also shipped: **type detection** (git SHA /
   issue key `ABC-123` / file ref incl. stack-trace `path:line:col`) with row icons, and a
   **⌘O "act on"** (`ClipAction`): reveal-on-demand for secrets · open http/https links ·
   reveal a file in Finder — all derived live from text so old clips work too. *Now also
   shipped:* the configurable integrations via **Settings → Developer** (`Preferences.devConfig`)
   — git SHA → open commit on a remote · issue key → open in a `{KEY}` tracker · `file:line` →
   open in VS Code/Cursor. **Bucket #2 complete.**
3. **Scoped/regex search + paste-stack**. *Shipped.* Search (`SearchQuery`): `type:<kind>`,
   `type:secret`/`is:secret` (live), `is:fav`, `app:<name>` (source app — captured in
   `Clip.sourceApp`, shown in the row), and `/regex/`, composable with fuzzy text. Paste-stack
   (`PasteStack`): ⇥ queues clips (numbered), ⇧⏎ pastes them in order via
   `dismiss(pasteSequence:)` — ⏎ stays single-paste.
4. **Encrypt at rest** — *shipped (text).* `Cryptor` does **app-layer** AES-GCM on the
   `text` field (`"enc:v1:"+base64`) with a 256-bit Keychain key, keyed-HMAC dedupe, and a
   lazy in-place migration of the existing store that vacuums + `secure_delete`s the freed
   plaintext. **App-layer, not SQLCipher** — SQLCipher is incompatible with the CloudKit-swap
   the model preserves; ciphertext syncs fine. Pulled ahead of search because #8 began
   *storing* secrets. Still owed when images land: **per-blob AES-GCM** for the image dir
   (the blob hole below) — reuse the same Keychain key.
5. **Concurrency machinery** — *groundwork shipped:* `SWIFT_STRICT_CONCURRENCY=complete` is on
   and the codebase is warning-clean — main-thread types are explicitly `@MainActor`, value
   snapshots (`ClipItem`, `ClipTransform`) are `Sendable`, Timer callbacks hop via
   `MainActor.assumeIsolated`. No runtime change yet. Still to do (with image capture): the
   background `NSManagedObjectContext` + serial worker so capture/hash/thumbnail run off-main,
   with `ClipItem` as the only actor-crossing type — then the Swift 6 language-mode flip.
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
