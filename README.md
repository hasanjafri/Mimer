# Mimer

**A fast, beautiful, privacy-first clipboard manager for macOS — the keeper of your copy history.**

Named after *Mímir*, the Norse guardian of memory and knowledge, Mimer remembers everything you copy — text, rich text, images, files, links — so you never lose a clip again. With permanent **Favorites that are saved forever**, instant fuzzy search, and a keyboard-first command palette.

## Why Mimer?

Today's options each force a compromise:

| App | The catch |
|-----|-----------|
| **CopyClip 2** ($7.99) | Text-only, dated UI; free version capped at 80 items to push the upgrade |
| **Maccy** (free, OSS) | Great privacy, but minimal/developer-focused, no sync, no polish |
| **Paste** ($29.99/yr) | Beautiful, but a *subscription* that stores your history in iCloud by default |
| **macOS 26 built-in** | Text-only, items expire, no pins, no search, no exclusions |

**Mimer combines the best of all of them:** Maccy's privacy + fair pricing, Paste's polish, full images/files support, permanent organized favorites, and a Raycast-grade command palette — **local-first, no subscription, beautifully native.**

## Status

🚧 **Pre-development.** This repo currently holds the research, analysis, and the design + engineering plan.

- [`docs/RESEARCH.md`](docs/RESEARCH.md) — competitive research & market analysis
- [`docs/DESIGN.md`](docs/DESIGN.md) — product concept & design direction
- [`docs/PLAN.md`](docs/PLAN.md) — engineering plan & roadmap *(written once key decisions are locked)*

## Tech

Native macOS app — **Swift 6 / SwiftUI + AppKit**, built with **Xcode 26**. Local-first storage; optional iCloud sync planned.
