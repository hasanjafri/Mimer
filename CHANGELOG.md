# Changelog

All notable changes to Mimer are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Mimer aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Fixed
- **Security:** auto-paste now re-verifies the target app is still frontmost before posting ⌘V, so a clip can't land in an app that stole focus.
- **Security:** with an unusable Keychain (ephemeral key) the store runs non-destructively — never migrating, vacuuming, or pruning away still-recoverable data.
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

[Unreleased]: https://github.com/hasanjafri/Mimer/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/hasanjafri/Mimer/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/hasanjafri/Mimer/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/hasanjafri/Mimer/releases/tag/v0.1.0
