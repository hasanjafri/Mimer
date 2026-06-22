# Mimer

[![CI](https://github.com/hasanjafri/Mimer/actions/workflows/ci.yml/badge.svg)](https://github.com/hasanjafri/Mimer/actions/workflows/ci.yml)

**A fast, private, developer-first clipboard manager for macOS — free and open source.**

Named after *Mímir*, the Norse guardian of memory and knowledge, Mimer lives in
your menu bar, remembers everything you copy, and gets out of the way until you
press **⇧⌘V**. It does what CopyClip and Maccy do — and then keeps going: it
understands what you copied (links, code, colors) and can *transform* it on the spot.

> Status: **v0.2.1 — live.** Notarized, Homebrew-installable, and auto-updating via
> Sparkle. Next up: leaning into the developer wedge (richer transforms, dev-aware clips,
> encrypted-at-rest privacy) — see [docs/ROADMAP.md](docs/ROADMAP.md).

---

## Why Mimer

Today's options each force a compromise:

| App | The catch |
|-----|-----------|
| **CopyClip 2** | "Favorites kept forever" is behind a purchase; dated, text-only UI |
| **Maccy** (free, OSS) | Great privacy, but deliberately minimal — no transforms, no type-awareness |
| **Paste** | Beautiful, but a *subscription* that stores history in iCloud by default |
| **macOS built-in** | Text-only, items expire, no pins, no search, no exclusions |

**Mimer's bet:** Maccy's privacy and fair (free) pricing, a Raycast-grade command
palette, and a developer toolbelt nobody else has — type-aware clips and
one-keystroke transforms — all local-first, no subscription, MIT-licensed.

## Features

- **Clipboard history** — everything you copy, newest first, surviving restarts.
- **Command palette (⇧⌘V)** — fuzzy search, ↑↓ to move, ⏎ to paste back into the app you were in.
- **Scoped search** — filter as you type: `type:link` (or `code`/`color`/`sha`/`issue`/`file`/`snippet`), `type:secret`, `app:Safari` (where you copied it), `is:fav`, and `/regex/` — combine with text, e.g. `app:Terminal git`.
- **Quick-paste (⌘1–⌘9)** — grab one of the top results instantly.
- **Paste-stack** — press **⇥** to queue several clips (numbered in order), then **⇧⏎** to paste them all in sequence — great for filling forms or assembling something from parts.
- **Type-aware clips** — links, code, colors, **git SHAs, issue keys (`ABC-123`), and file paths / stack-trace `file:line`** each get their own glyph; hex colors show a live swatch.
- **Image clips** — copied images are captured with a thumbnail in the list and pasted right back; like all clips, they're **encrypted at rest** (the blob files hold only ciphertext).
- **⌘O — act on a clip** — context-aware: reveal a masked secret, open a link in your browser, or reveal a file path / `file:line` in Finder. Set a git remote, issue tracker, or editor in **Settings → Developer** and ⌘O also opens a commit SHA's page, an issue key in your tracker, or a `file:line` in VS Code/Cursor.
- **⌘K transforms** — for the selected clip, each with a live preview and shown only when it applies:
  - *General:* `UPPER`/`lower`/`Title`, `camelCase`/`snake_case`, trim, slugify, Base64 encode/decode, URL encode/decode, JSON pretty-print/minify.
  - *Lists:* sort lines, dedupe lines, reverse lines.
  - *Developer:* **JSON → TypeScript**, **Decode JWT**, **strip tracking params** from a URL, **decode a query string**, **Unix ↔ ISO 8601** timestamps — with more coming (diff two clips, chains, paste-as-plain).
- **Favorites** — ⌘D (or the ★) keeps a clip forever, pinned in its own section.
- **Snippets** — author reusable text (signatures, boilerplate) that lives in the palette forever.
- **Secret-aware** — detected API keys, tokens, and private keys are **masked** in the list (`AWS key ••••1234`, with a 🔒) so they're not on screen during a screenshare. They're still stored locally and pasted in full — unlike cloud tools, Mimer doesn't drop your secrets, it just hides them from view. Toggle in Privacy settings.
- **Pause + per-app exclusions** — stop recording on demand, or never record while chosen apps are frontmost. Password managers are always ignored.
- **Auto-paste (optional)** — ⏎ pastes straight into your previous app once you grant the one permission; otherwise the clip is on your clipboard for ⌘V.
- **Launch at login**, configurable history size, and a configurable menu height.

Planned: file clips, more transforms, OCR on images.

## Keyboard

| Key | Action |
| --- | --- |
| `⇧⌘V` | Open / close the palette |
| `↑` `↓` | Move selection |
| `⏎` | Paste the selected clip |
| `⌘1`–`⌘9` | Paste that result |
| `⌘K` | Transform the selected clip |
| `⌘D` | Favorite / unfavorite |
| `⌫` | Delete the selected clip |
| `esc` | Close (or leave transform mode) |

## Privacy

Mimer stores history in a local Core Data database under
`~/Library/Application Support/Mimer/` and makes **no network requests**. Clip
contents **and the captured source-app name** are **encrypted at rest** (AES-GCM; the
key lives in your macOS Keychain, this-device-only) — the sqlite file holds only
ciphertext, and upgrading encrypts your existing history in place and scrubs the old plaintext. It also ignores clips
marked transient/concealed/auto-generated (the standard `org.nspasteboard.*` hints
password managers and other tools set) and ships with a built-in password-manager
blocklist (1Password, Bitwarden, Apple Passwords, KeePassXC, …). Reading the
clipboard needs no special permission; auto-paste is opt-in and uses macOS's
post-event permission (not Accessibility).

> Encryption is at-rest only: clips are decrypted in memory to show and paste them,
> and the key is local to this Mac (not iCloud-synced), so history can't be read
> from the DB file alone. If you lose the Keychain key (e.g. migrating Macs without
> it), previously-stored history becomes unreadable — that's inherent to at-rest encryption.

## Install

**Download** (signed + notarized): grab the latest `Mimer-x.y.z.dmg` from
[Releases](https://github.com/hasanjafri/Mimer/releases/latest), open it, and drag
Mimer to Applications. Requires macOS 14+.

**Homebrew:**

```sh
brew install --cask hasanjafri/tap/mimer
```

**Build from source:**

```sh
brew install xcodegen          # one-time
git clone https://github.com/hasanjafri/Mimer.git
cd Mimer
xcodegen generate              # writes Mimer.xcodeproj from project.yml
open Mimer.xcodeproj           # ⌘R to run, or:
xcodebuild -scheme Mimer -configuration Release build
```

Requires macOS 14+ and the Xcode command-line tools.

## Tech

Swift + SwiftUI (`MenuBarExtra`) with an AppKit `NSPanel` for the nonactivating
command palette, Core Data for history, and
[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for the
global hotkey. The Xcode project is generated from `project.yml` via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (so the `.xcodeproj` is not
committed). See [`docs/`](docs/) for the research, design, plan, and reviews.

## Contributing

Issues and PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for build/test (run
`xcodegen generate` first), [CHANGELOG.md](CHANGELOG.md) for what's changed, and
[SECURITY.md](SECURITY.md) to report anything security-sensitive privately.

## License

[MIT](LICENSE) — © 2026 Hasan Jafri.
