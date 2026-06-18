# Mimer — Product Concept & Design Direction

*The product vision and the design language. Engineering specifics live in `PLAN.md`.*

---

## 1. Concept & positioning

**Mimer is the keeper of your clipboard.** It quietly remembers everything you copy and makes any of it reachable in under a second — beautiful enough to enjoy, private enough to trust, powerful enough to replace CopyClip, Maccy, *and* Paste.

> **Tagline candidates:** "Your clipboard, remembered." · "Never lose a copy again." · "The clipboard, with a memory."

**Positioning:** *Maccy's privacy + Paste's polish + images/files + permanent favorites — local-first, no subscription.*

---

## 2. Target users

- **The privacy-conscious pro** who likes Maccy but wants it to look good and handle images/files.
- **The Paste refugee** who loves the polish but resents the $30/yr subscription and cloud-by-default.
- **The "I won't pay $10 for CopyClip 2" user** who wants something modern and generous.
- **The keyboard-driven power user** who lives in Spotlight/Raycast and wants the same speed for the clipboard.

---

## 3. Design principles

1. **Invisible until summoned, instant when needed.** No dock icon; a calm menu-bar presence; a global hotkey that opens a fast panel.
2. **Keyboard-first, mouse-friendly.** Everything is reachable from the keyboard; the mouse is never required but always works.
3. **Native, not themed.** One beautiful design that respects macOS 26 (Tahoe) — *not* ten gaudy color themes. Light/dark + system accent.
4. **Private by default.** Local-first storage; passwords and "concealed"/transient clips are never recorded; clear, honest permission asks.
5. **Content-aware.** Text, rich text, images, files, links, colors, and code each get a tailored preview and tailored actions.
6. **Forever means forever.** Favorites and Pinboards are never auto-pruned, never expire — the antidote to the OS built-in's disappearing history.

---

## 4. The core experience

### a) The command palette (the headline UX)
A centered, floating **search-first panel** (think Spotlight/Raycast) summoned with a global hotkey (default **⇧⌘V**):

```
┌─────────────────────────────────────────────────────────┐
│  🔍  Search your clipboard…                        ⌘F ★  │
├───────────────────────────────┬─────────────────────────┤
│ ▸ Hello world                 │                         │
│ ▸ https://example.com    🔗   │      Live preview       │
│ ▸ ⬛ Screenshot.png      🖼   │   of the selected clip  │
│ ▸ #4F46E5                🎨   │   (text / image / file  │
│ ▸ func paste() { … }     </>  │    / link / code …)     │
│   ★ Favorites · Recents · All │   + source app, time    │
└───────────────────────────────┴─────────────────────────┘
   ↑↓ navigate · ⏎ paste · ⌥⏎ paste plain · ⌘1–9 quick · ⌘F favorite
```

- **Left:** results list with type glyphs, grouped/filterable by **Recents · Favorites · All**, and by type (text, image, file, link, color, code).
- **Right:** rich live preview of the highlighted clip + metadata (source app icon, timestamp, size, type).
- **Keys:** type to fuzzy-search instantly · ↑/↓ to move · ⏎ to paste · ⌥⏎ to paste as plain text · ⌘1–9 to paste any of the top items · ⌘F to favorite · ⌫ to delete.

### b) Rich, content-aware clips
- **Text / rich text** (preserve or strip formatting), **images** (PNG/TIFF with thumbnail), **files** (icon + path), **links** (title + favicon), **color codes** (swatch), **code** (monospaced, optional syntax highlight).

### c) Favorites & Pinboards — "saved forever"
- A dedicated **Favorites** space, separate from the rolling history, that **never expires or gets pruned**.
- Organize into **Pinboards** (boards/folders) and/or **tags** — e.g. "Email signatures," "Addresses," "Code snippets."
- Drag to reorder; one-keystroke favorite/unfavorite from the palette.
- This is the direct, *much* stronger answer to CopyClip 2's basic pin.

### d) Menu-bar companion
A lightweight menu-bar icon: click for a compact list of recent + favorite clips and quick actions (open palette, pause recording, preferences). The palette is for power; the menu bar is for glanceability.

### e) Snippets (planned)
Saved canned text (signatures, replies, boilerplate) — favorites that you author rather than copy.

---

## 5. Visual language

- **Platform-native macOS 26 (Tahoe).** Embrace the current design language — **Liquid Glass** materials, vibrancy/translucency on the floating panel, generous corner radii, soft depth/shadow.
- **Typography:** SF Pro (UI), SF Mono (code/clips). Clear hierarchy; comfortable line-height for previews.
- **Color:** restrained, system-accent-aware, plus one signature Mimer accent (a deep "memory" indigo/teal) used sparingly for favorites/brand moments. Full light & dark.
- **Iconography:** SF Symbols throughout; a custom, memorable app/menu-bar icon (a nod to memory/Mímir — e.g. a stylized well/knot/spark).
- **Motion:** quick, spring-based, 60fps. Panel summon ~150ms; subtle "captured" pulse when a new clip is recorded; satisfying paste confirmation. Nothing slow or bouncy-for-its-own-sake.
- **Empty/onboarding states:** warm, instructional, never blank.

---

## 6. Screens / surfaces

1. **Command palette** (primary) — search + list + preview.
2. **Menu-bar dropdown** — recents, favorites, pause, settings.
3. **Favorites / Pinboards manager** — fuller window for organizing saved clips.
4. **Settings** — General (launch at login, hotkey, history size), Privacy (excluded apps, pause, ignore rules), Appearance, Sync (when added), About.
5. **Onboarding** — welcome → set hotkey → permissions (Accessibility for auto-paste, explained honestly) → optional **Import from CopyClip** → done.

---

## 7. Feature set

**Ship in v1 (MVP → 1.0):** clipboard history (text, rich text, images, files, links, colors); the command palette; instant fuzzy search; Favorites + Pinboards (never expire); paste / paste-as-plain / ⌘1–9 quick paste; global hotkey; menu-bar companion; app exclusions + pause + auto-ignore passwords; light/dark; launch-at-login; import-from-CopyClip; settings.

**Later (1.x → 2.0):** snippets/templates; iCloud sync (Mac↔Mac); iOS/iPad companion with keyboard; OCR on image clips; paste stacks; smart actions (e.g. open link, save image); Quick Look; multiple-clip merge.

---

## 8. Why someone switches to Mimer

| Coming from | What they gain |
|---|---|
| **CopyClip 1/2** | Modern UI, command palette, **images & files**, real favorites/pinboards, fairer pricing, 1-click import |
| **Maccy** | Same privacy + speed, but **gorgeous**, with images/files, favorites organization, and (later) sync |
| **Paste** | The polish **without the $30/yr subscription** and without cloud-by-default |
| **macOS 26 built-in** | Search, pins, **favorites that never expire**, images/files, exclusions, real UX |
