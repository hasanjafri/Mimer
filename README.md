# Mimer

[![CI](https://github.com/hasanjafri/Mimer/actions/workflows/ci.yml/badge.svg)](https://github.com/hasanjafri/Mimer/actions/workflows/ci.yml)

**A fast, private, developer-first clipboard manager for macOS — free and open source.**

Named after *Mímir*, the Norse guardian of memory, Mimer lives in your menu bar,
remembers everything you copy, and gets out of the way until you press **⇧⌘V** — then
it's a fast command palette that understands what you copied and can transform it on the spot.

<p align="center">
  <img src="docs/media/hero.png" alt="Mimer command palette showing type-aware clipboard history" width="640">
</p>

> Status: **v0.2.2 — live.** Notarized, Homebrew-installable, and auto-updating via
> Sparkle. **Website:** [mimer.hasanjafri.com](https://mimer.hasanjafri.com/) ·
> See [CHANGELOG.md](CHANGELOG.md) for what's new and [docs/ROADMAP.md](docs/ROADMAP.md) for what's next.

---

## Why Mimer

I built Mimer because I got tired of my old clipboard manager (CopyClip) — and then it
wanted me to pay for **CopyClip 2** to keep going. A clipboard manager is something you
live in all day; it should be fast, private, and free. So I made the one I wanted:

- **Type-aware** — it knows a link from code from a color from a git SHA, and shows the right glyph (with a live swatch for colors).
- **⌘K transforms** — reshape a clip in place with a live preview: case, slugify, Base64/URL, JSON pretty-print, **JSON → TypeScript**, **decode a JWT**, **Unix ↔ ISO** time, and more.
- **Hover to read the whole clip** — a preview card shows the full text (long clips keep their start *and* end, never just the start), formatted for what it is: JSON re-wrapped, diffs coloured, a URL's host and tracking params picked out.
- **Built for developers** — scoped search (`type:`, `app:`, `/regex/`), a paste-stack, and **⌘O** to open a commit / issue / `file:line` straight in your tools.
- **Private by default** — local-only, no telemetry, no subscription; history is **encrypted at rest** and detected secrets are masked on screen.

Free and open source (MIT) — and it stays that way. If you've used **Maccy** or
**CopyClip**, think of Mimer as a free, faster, developer-focused alternative.

## Features

**Search as you type** — fuzzy match, with scoped filters (`type:`, `app:`, `is:fav`, `/regex/`):

<p align="center">
  <img src="docs/media/search.gif" alt="Filtering the clipboard history by typing 'git'" width="620">
</p>

**⌘K transforms** — every transform shows a live preview, and only the ones that apply are listed:

<p align="center">
  <img src="docs/media/transform.png" alt="⌘K transform menu with live previews" width="620">
</p>

**Paste-stack** — queue several clips with **⇥**, then **⇧⏎** to paste them all in order:

<p align="center">
  <img src="docs/media/paste-stack.png" alt="Paste-stack with numbered queued clips" width="620">
</p>

**Hover preview** — pause on a row (in the menu or the palette) and the whole clip appears
beside it, read the way it was written:

<p align="center">
  <img src="docs/media/preview-card.png" alt="Three Mimer hover preview cards: JSON re-wrapped for reading, a diff with coloured +/- lines and a +10 -5 badge, and code with comments, keywords and strings" width="820">
</p>


- long clips elide the **middle**, never the ends — the tail is usually what tells two
  near-identical clips apart;
- **JSON** is re-wrapped for reading (whitespace only — key order and values are untouched),
  **diffs** show their `+`/`−` lines in colour with a `+12 −3` badge, **code** gets comments,
  strings and keywords, and a **URL** shows its host with any tracking parameters called out;
- the footer carries the shape and provenance: characters / words / lines, the app it came
  from, when you copied it, and the **⌘O** action for it;
- masked secrets stay masked here too, and images preview at a size you can actually judge.

Turn it off in **Settings → General** if you'd rather not have it.

### Everything else

- **Clipboard history** — everything you copy, newest first, surviving restarts; quick-paste a top result with **⌘1–⌘9**.
- **Type-aware clips** — links, code, colors, **git SHAs, issue keys (`ABC-123`), and file paths / stack-trace `file:line`** each get their own glyph; hex colors show a live swatch.
- **Image clips** — copied images are captured with a thumbnail in the list and pasted right back; like all clips, they're **encrypted at rest** (the blob files hold only ciphertext).
- **⌘O — act on a clip** — context-aware: reveal a masked secret, open a link in your browser, or reveal a file path / `file:line` in Finder. Set a git remote, issue tracker, or editor in **Settings → Developer** and ⌘O also opens a commit SHA's page, an issue key in your tracker, or a `file:line` in VS Code/Cursor.
- **More ⌘K transforms** (beyond the previews shown above) — `camelCase`/`snake_case`, sort/dedupe/reverse lines, **strip URL tracking params**, **decode a query string**, JSON pretty/minify — each shown only when it applies.
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
| `⇧⌘V` | Open / close the palette (rebindable in Settings → General) |
| `↑` `↓` | Move selection |
| `⏎` | Paste the selected clip |
| `⌘1`–`⌘9` | Paste that result |
| `⌘K` | Transform the selected clip |
| `⌘D` | Favorite / unfavorite |
| `⌫` | Delete the selected clip |
| `esc` | Close (or leave transform mode) |

The palette hotkey and history limits are configurable in **Settings → General**:

<p align="center">
  <img src="docs/media/settings.png" alt="Mimer settings: rebindable shortcut and history limits" width="460">
</p>

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

On first launch Mimer walks you through the basics (and auto-paste is opt-in — it works fully without any permission):

<p align="center">
  <img src="docs/media/onboarding.png" alt="Mimer first-run onboarding" width="440">
</p>

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

## Command-line tool (`mimer`)

Mimer ships a tiny `mimer` CLI that exposes the same **⌘K transform engine** as
the app (the exact `ClipTransform` code, shared — no duplication). It's the Unix
thing: read text from an argument or stdin, write the result to stdout. It touches
no clipboard history and needs no running app — a pure function over text, so any
script or terminal AI agent can call it.

```sh
echo '{"id":1,"name":"a"}' | mimer json-to-ts   # → interface Root { … }
mimer decode-jwt "$TOKEN"
pbpaste | mimer slugify | pbcopy
mimer list                                       # every transform
```

`mimer` (and `mimer-mcp`, below) ship **inside the app**. Put them on your `PATH` with one
click: **Settings → Developer → Install Command-Line Tools**, which symlinks them into
`/usr/local/bin` (if that isn't writable, it copies the `ln -s …` commands to your clipboard
so you can run them yourself). They live at `Mimer.app/Contents/Resources/mimer` if you'd
rather link them by hand.

## AI access — MCP server (`mimer-mcp`)

Mimer ships an [MCP](https://modelcontextprotocol.io) server so a local AI assistant
(Claude Desktop, Claude Code) can **use** Mimer: run its transforms, and — if you allow
it — read your recent and searched clips.

**Off by default.** Reading clip history requires you to turn on
**Settings → Privacy → “Allow local AI tools to read clips.”** While that's off, the app
opens no port and the server can read nothing — the gate is enforced by the app, not by the
server's good behavior. Everything stays on your Mac over a local-only channel, and while
masking is on, detected secrets are hidden from the AI entirely (kept off the surface, not
just masked, so `search_clips` can't be used to probe them). The **transform** tools work
with no history access and no toggle. Note: while enabled, the local channel isn't
authenticated, so any process on your Mac can query it — it's meant to be turned on only
while you want an assistant to have access.

Tools: `list_transforms`, `transform`, `recent_clips`, `search_clips`.

Connect it (install the tools first, then use the `/usr/local/bin/mimer-mcp` symlink — or the
`Mimer.app/Contents/Resources/mimer-mcp` path directly):

```jsonc
// Claude Desktop — ~/Library/Application Support/Claude/claude_desktop_config.json
{
  "mcpServers": {
    "mimer": { "command": "/usr/local/bin/mimer-mcp" }
  }
}
```

```sh
# Claude Code
claude mcp add mimer /usr/local/bin/mimer-mcp
```

Then ask your assistant to, e.g., “find the JSON I copied earlier and turn it into a TypeScript type.”

## Feedback

Mimer collects **no telemetry** — the only way your experience reaches me is if you
tell me. There's a **Send Feedback…** item in the menu-bar dropdown (and in
Settings → About) that opens a pre-filled bug report; ideas and questions go to
[Discussions](https://github.com/hasanjafri/Mimer/discussions). Whatever's rough,
missing, or delightful — I'd love to hear it.

## Contributing

Issues and PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for build/test (run
`xcodegen generate` first), [CHANGELOG.md](CHANGELOG.md) for what's changed, and
[SECURITY.md](SECURITY.md) to report anything security-sensitive privately.

## License

[MIT](LICENSE) — © 2026 Hasan Jafri.
