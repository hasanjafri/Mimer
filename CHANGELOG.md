# Changelog

All notable changes to Mimer are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Mimer aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Hover preview card** — pause on a clip in the menu or the palette and the full clip appears
  in a card beside the list. Long clips keep their start **and** their end (the middle is
  elided, with the hidden character count shown), so near-identical clips are finally
  distinguishable. The footer shows characters / words / lines, the source app and its icon,
  when it was copied, and the ⌘O action. Arrowing through the palette shows the card too.
  Toggle in **Settings → General**.
- **Content-aware formatting inside the preview** — minified **JSON** is re-wrapped for reading
  (a whitespace-only pass: key order and values are untouched, and the card says `formatted`),
  **diffs** colour their `+`/`−`/`@@` lines and carry a `+12 −3` badge, **code** gets comments,
  strings, numbers and keywords, and **URLs** highlight the host and flag tracking parameters.
  Search terms are highlighted inside the preview — including in the middle of a long clip.
- Masked secrets stay masked in the preview; images preview large with their dimensions,
  encoding, and file size.

## [0.3.0] - 2026-07-27

### Added
- **`mimer` command-line tool** — run Mimer's ⌘K transforms in a terminal or a script:
  `echo '{"id":1}' | mimer json-to-ts`, `mimer decode-jwt "$TOKEN"`, `mimer list`. Shares the
  app's exact transform engine; touches no clipboard history.
- **AI access via MCP** — an opt-in `mimer-mcp` [Model Context Protocol](https://modelcontextprotocol.io)
  server lets a local AI assistant (Claude Desktop/Code) run Mimer's transforms and — only when
  you turn it on — read your recent and searched clips. **Off by default** (Settings → Privacy);
  local-only; while masking is on, detected secrets are kept off the AI entirely.
- **Bundled tools + one-click install** — `mimer` and `mimer-mcp` ship inside the app; install
  them to your PATH from **Settings → Developer → Install Command-Line Tools**.
- **In-app feedback** — a **Send Feedback** item in the menu bar and Settings → About opens a
  pre-filled bug report (Mimer version + macOS auto-filled); GitHub Discussions for ideas.

## [0.2.2] - 2026-06-22

### Added
- **Scoped & regex search** in the palette — `type:`, `is:favorite`, `app:"Name"`, and `/regex/`.
- **Paste stack** — queue clips with `⇥` and paste them in order with `⇧⏎`.
- **Source-app capture** — clips remember which app they came from; filter with `app:`.
- **Configurable act-on integrations** — open a clip as a commit / issue / in your editor (Settings → Developer).
- **More ⌘K transforms** — JSON → type, line operations, additional case conversions.
- **Image clips** — copied images are captured with a thumbnail and pasted back; encrypted at rest like every clip.
- **Rebindable palette hotkey** — change the ⇧⌘V shortcut in Settings → General.

### Changed
- Concurrency groundwork toward Swift 6 (`strict-concurrency=complete`, clean).
- Async, bounded image-thumbnail loading (off-main downsample).
- Accessibility: VoiceOver labels on icon-only buttons (favorite, remove-exclusion, menu-bar status) and Dynamic Type scaling for the onboarding/about/menu-action glyphs.

### Fixed
- **Security:** auto-paste now re-verifies the target app is still frontmost before posting ⌘V, so a clip can't land in an app that stole focus.
- **Security:** with an unusable Keychain (ephemeral key) the store runs non-destructively — never migrating, vacuuming, or pruning away still-recoverable data.
- **Security:** excluded / password-manager apps are now honored even across a fast focus switch — a copy made there is discarded when focus leaves, closing the poll-tick race.
- Settings window no longer clips its taller panes; menu rows are a uniform height so image rows don't mis-size the menu.

## [0.2.1] - 2026-06-21
### Fixed
- `CFBundleVersion` is now a monotonic build number so Sparkle reliably offers updates.

## [0.2.0] - 2026-06-21
### Added
- Mouse/hover feedback when selecting a clip; redesigned menu-bar dropdown.
- CI/CD: build + test on PRs, a release workflow, and branch protection on `main`.
### Fixed
- Appcast signing in the release pipeline (sign via `--ed-key-file` stdin).

## [0.1.0] - 2026-06-21
First public release — a fast, private, developer-first clipboard manager for macOS.
### Added
- Clipboard history + a Spotlight-style palette (`⇧⌘V`): fuzzy search, `⌘1–9` quick-paste.
- Type-aware clips — links, code, colors (with live swatches).
- `⌘K` transforms with live previews: UPPER/lower/Title, trim, slugify, Base64, URL, JSON pretty/minify.
- Favorites (kept forever) + authored snippets.
- Pause, per-app exclusions, a built-in password-manager blocklist.
- Optional auto-paste, launch at login, and auto-update (Sparkle). Local-only, no telemetry. MIT.

[Unreleased]: https://github.com/hasanjafri/Mimer/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/hasanjafri/Mimer/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/hasanjafri/Mimer/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/hasanjafri/Mimer/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/hasanjafri/Mimer/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/hasanjafri/Mimer/releases/tag/v0.1.0
