# Mimer — Engineering Plan & Roadmap (v2, post-review)

*Native macOS clipboard manager. Reviewed via `/autoplan` (CEO + Design + Engineering lenses, with independent review agents). Full findings + audit trail: [`REVIEW.md`](REVIEW.md).*

---

## 1. Locked decisions (updated after review)

| Decision | Choice | Consequence |
|---|---|---|
| **Monetization** | **Completely free, forever** + **open-source (MIT)** | No IAP/licensing. Sustainability = open-source: contributors share the macOS-breakage maintenance load. |
| **Distribution** | **Direct-download first** — Developer ID notarized `.dmg` + Sparkle auto-update + **Homebrew Cask**; public **GitHub from day 1**; **Mac App Store later** | The real growth engine for a free Mac utility (Show HN, r/macapps, awesome-macos, Homebrew). v1 ships **non-sandboxed**, which unlocks clean auto-paste + import. Keep APIs MAS/sandbox-compatible so a later App Store build is feasible. |
| **Sync & scope** | **Local-only Mac v1**, CloudKit-valid model from day 1 | Sync = the first post-1.0 headline. |
| **v1 feature scope** | **Full feature set** (your call) | Kept full. **Release valve:** Tags, multi-pinboard organization, and CopyClip import may slip to 1.1 if 1.0 timelines stretch. |

---

## 2. Tech stack

| Concern | Choice | Why |
|---|---|---|
| Language / tooling | Swift 6, Xcode 26; **XcodeGen** (`project.yml`) for a git-friendly, reproducible project | Already installed; XcodeGen avoids hand-editing `.xcodeproj`. |
| UI | SwiftUI views + thin AppKit plumbing | AppKit only for the floating panel + status item. |
| Menu-bar item | `MenuBarExtra` (SwiftUI) | Native dropdown companion. (Note: opening the Settings scene from `MenuBarExtra` is unreliable across releases — use a small AppKit shim.) |
| Command palette | A nonactivating `NSPanel` subclass hosting SwiftUI via `NSHostingView` | The only way to get a key-able Spotlight-style centered panel from an `LSUIElement` agent. See §4 for the focus model (it's the #1 technical risk). |
| App lifecycle | SwiftUI `App` + `NSApplicationDelegateAdaptor`; `LSUIElement` agent | Panel/hotkey/monitor owned by the delegate so they survive view teardown. |
| Global hotkey | `KeyboardShortcuts` (Sindre Sorhus, SPM) | Wraps `RegisterEventHotKey` (only sandbox-legal global-hotkey API). **Blocklist Option-only combos** in the recorder (macOS 15 bug FB15168205); default ⇧⌘V is fine. |
| Auto-paste | `CGEvent.post` gated by **`kTCCServicePostEvent`** (`CGRequestPostEventAccess` / `CGPreflightPostEventAccess`) | NOT the Accessibility AX API; NOT AppleScript (`apple-events` temp-exception is MAS-rejected). Sandbox-compatible; this is Maccy's shipped approach. |
| Storage | Core Data + `NSPersistentCloudKitContainer` (CloudKit-valid from day 1) | Mature; external-binary blobs; sync is later a container-config change, not a schema migration — *if* the model is valid now (§5). |
| Search | In-memory subsequence fuzzy over a lightweight projection (v1) | Fine at ~10k items **iff blob attributes are never faulted into the search/list path**. FTS5 is not a drop-in for fuzzy (different match semantics) — add later only as a prefilter, not a replacement. |
| Launch at login | `SMAppService.mainApp` (macOS 13+) | Handle `.requiresApproval` / throw, don't assume success (§7). |
| Clipboard capture | `NSPasteboard` + `changeCount` polling @ **500ms** | Cheap (integer compare; read contents only on change). Below ~250ms buys nothing and costs battery. |

---

## 3. Permissions & distribution reality (corrected)

1. **Read clipboard** — `NSPasteboard.general` readable with no entitlement. ✓
2. **Global hotkey & launch-at-login** — work via `KeyboardShortcuts` and `SMAppService`. ✓
3. **Auto-paste** — `CGEvent.post` + `kTCCServicePostEvent` (request via `CGRequestPostEventAccess`). **Sandbox-compatible** (Apple DTS; shipped by Maccy on the MAS). Because **v1 is direct/non-sandboxed, there is no App Review 2.4.5 risk → auto-paste is a first-class v1 feature** (the hero flow), with manual ⌘V as the universal fallback. There is **no reliable success signal** for a synthesized paste, so never show a false "Pasted" confirmation (apps with secure fields / custom paste may ignore it). The later MAS build keeps auto-paste opt-in + TestFlight-validated against 2.4.5.
4. **CopyClip import (corrected)** — a single-file bookmark is broken: it doesn't cover the `-wal`/`-shm` sidecars, reading a *live* WAL DB risks corruption/`SQLITE_BUSY`, and macOS 14+ interposes a non-suppressible cross-container consent prompt. **Correct flow:** `NSOpenPanel` with `canChooseDirectories` → user grants the *enclosing folder* → open the source **read-only** and `VACUUM INTO` a clean, checkpointed copy in **our** container → read & map that copy. Also offer a neutral "import a file you exported yourself" path. (Non-sandboxed v1 eases this; a later MAS build still faces the consent prompt + competitor-container optics, so import may stay direct-build-only or move to 1.1.)
5. **Privacy** — "Data Not Collected." Revisit the label when iCloud sync ships (syncing to the user's own private CloudKit DB still generally qualifies as not collected by the developer).
6. **CloudKit-readiness now** — the v1 model must pass CloudKit schema validation even with sync off (§5).

**Distribution pipeline (v1):** Developer ID signing → notarization (`notarytool`) → stapled `.dmg` (`create-dmg`) → Sparkle appcast for auto-update → Homebrew Cask. Public GitHub repo, MIT.

---

## 4. Architecture

```
MimerApp (SwiftUI App, LSUIElement, non-sandboxed Developer ID v1)
├── AppDelegate            – owns panel + hotkey + monitor lifecycle
├── MenuBarExtra           → MenuBarView (recents, favorites, pause, settings)
├── PalettePanel (NSPanel) → PaletteView  (search · list · live preview)
├── Settings scene         → General / Privacy / Appearance / About
│
├── Core
│   ├── ClipboardMonitor   – 500ms changeCount poll on a background queue; race-safe capture; ignore rules; dedup
│   ├── Paster             – set pasteboard; auto-paste via CGEvent.post (focus-return FIRST); manual-⌘V fallback
│   ├── HotkeyManager      – KeyboardShortcuts wiring
│   └── LaunchAtLogin      – SMAppService (handles .requiresApproval)
│
├── Data (Core Data, CloudKit-valid)
│   ├── ClipStore          – CRUD, search (projection-only), favorites, pinboards
│   └── Models             – Clip, ClipKind, Pinboard, Tag
│
├── Features
│   ├── Onboarding         – welcome · hotkey · (contextual permission asks) · import
│   └── CopyClipImporter   – folder grant → VACUUM INTO copy → read-only → map
│
└── DesignSystem           – colors, type, materials, motion, reusable views/icons
```

**Palette focus model (the #1 risk — spike it in Phase 0):**
- `NSPanel` subclass overriding `canBecomeKey { true }` (+ `canBecomeMain`); style includes `.nonactivatingPanel`; level `.floating`+; `collectionBehavior` includes `.canJoinAllSpaces` + `.fullScreenAuxiliary`.
- `makeKeyAndOrderFront(nil)` **after** positioning so the search field is first responder immediately. Do **not** rely on `becomesKeyOnlyIfNeeded`.
- Do **not** call `NSApp.activate(ignoringOtherApps:)` (that steals full activation and breaks "paste into the app I was in"). The nonactivating panel keeps the prior app frontmost.
- On dismiss/paste: `orderOut`, ensure prior-app focus is restored **before** posting ⌘V (the ordering race is the #1 practical auto-paste bug).

**Capture correctness:**
- Background queue + background Core Data context (never block UI reading large images/RTF).
- **Race-safe:** snapshot `changeCount` → read all representations → re-read `changeCount`; if changed, discard and let the next tick re-capture.
- **Ignore:** `org.nspasteboard.TransientType`, `ConcealedType`, `AutoGeneratedType`, `RestoredType` (avoid feedback loops from our own paste), a password-manager bundle blocklist (1Password, etc.), and the user's excluded apps.
- **Representation precedence:** fileURL > image > RTF/HTML > plain text; **always** also store a plain-text fallback for search.
- **Dedup:** content hash; if equal to the most-recent clip, bump `lastUsedAt` instead of inserting.

---

## 5. Data model (CloudKit-valid from day 1)

- `Clip` — `id`, `kind`, `plainText`, `richData` (external binary), `imageData` (external binary), `thumbnailData`, `fileURLs`, `sourceAppBundleID`, `sourceAppName`, `createdAt`, `lastUsedAt`, `isFavorite`, `pinOrder`, `pinboard` (rel + inverse), `tags` (rel + inverse).
- `Pinboard` — `id`, `name`, `symbol`, `sortIndex`, `clips` (rel + inverse).
- `Tag` — `id`, `name`, `clips` (rel + inverse).

**CloudKit constraints to honor NOW (else a later schema migration is forced):**
- Every relationship has an **inverse**.
- Delete rules are **Nullify/Cascade**, never **Deny**.
- **No `Ordered` relationships** → ordering (incl. Pinboard drag-reorder) uses the explicit `sortIndex`/`pinOrder` Int and sorts in-app.
- **No unique constraints** → identity/dedup is app-enforced (content hash).
- Large images = external binary; **lists always render from `thumbnailData`**; aggressive size cap at capture.
- **Pruning** removes old rolling-history clips by a configurable cap; **favorites/pinboard clips are exempt** ("saved forever").
- **v1 acceptance test:** `NSPersistentCloudKitContainer.initializeCloudKitSchema()` succeeds even with sync disabled.

---

## 6. Roadmap

**Phase 0 — Scaffold + de-risking spikes** *(S/M)*
- XcodeGen `project.yml`, SPM deps (`KeyboardShortcuts`), Developer ID + notarize config stub, `LSUIElement` menu-bar agent skeleton, DesignSystem stub, CI build.
- **Spike A:** real-build `CGEvent.post` ⌘V + `CGRequestPostEventAccess` round-trip **and** the NSPanel focus / first-responder / focus-return-before-⌘V ordering. (De-risks the palette *and* auto-paste together.)
- **Spike B:** `NSOpenPanel` folder grant → `VACUUM INTO` copy → read-only open of a **real CopyClip DB** on macOS 15. (De-risks import.)

**Phase 1 — Clipboard engine + history** *(M)*: `ClipboardMonitor` (race-safe, ignore rules, dedup, off-main), Core Data store, capture text first, menu-bar dropdown of recents, copy-back. *Milestone: working private history.*

**Phase 2 — Command palette + auto-paste** *(L)*: the `NSPanel` palette, global hotkey, instant fuzzy search, list + live preview, full keyboard nav, ⌘1–9, paste / paste-plain, **auto-paste (first-class) with manual fallback**. *Milestone: the headline UX.*

**Phase 3 — Favorites & Pinboards** *(M)*: one-key favorite, never-expire guarantee, pinboards (+ tags — release-valve to 1.1), organize/reorder via `sortIndex`. *Milestone: the "saved forever" promise.*

**Phase 4 — Rich content types** *(M)*: images, files, links, colors, code — each with a tailored preview + primary/secondary actions (open link, reveal file, copy color as hex/rgb).

**Phase 5 — Privacy & Settings** *(M)*: excluded apps, pause (with ambient menu-bar indicator), ignore rules, history cap, appearance, launch-at-login (+ `.requiresApproval` UX), Settings panes.

**Phase 6 — Onboarding + CopyClip import** *(M)*: first-run (hotkey, **contextual** permission asks — app is fully functional with zero permissions), guided import (corrected flow).

**Phase 7 — Polish & QA** *(M)*: motion + reduce-motion, the missing states (§10), full accessibility, performance (10k clips, image memory), custom app + menu-bar icon.

**Phase 8 — Release (direct)** *(M)*: Developer ID + notarize + stapled `.dmg` + Sparkle appcast + Homebrew Cask.

**Phase 9 — Launch & distribution** *(S, but essential)*: GitHub README with GIFs, Show HN, r/macapps + r/MacOS, awesome-macos PR, Product Hunt. *(The CEO review's critical gap — shipping ≠ distribution.)*

**Mac App Store build & iCloud sync** follow as the first post-1.0 work.

---

## 7. Key risks & mitigations

| Risk | Mitigation |
|---|---|
| Palette focus / focus-return ordering (top technical risk) | Spike A in Phase 0; explicit "restore focus before ⌘V" step. |
| Auto-paste | Low risk on direct (clean `CGEvent.post`); MAS-later → opt-in + TestFlight vs 2.4.5. No false "pasted" toast (F4). |
| CopyClip import | Redesigned (folder grant + `VACUUM INTO` + read-only). MAS optics → direct-only / 1.1. |
| Enabling iCloud later | It's a real migration (initial export + cross-device dedup), **not** a flag-flip. Keep model CloudKit-valid from day 1 + the schema test. |
| Large blobs over CloudKit (v2) | ~1MB field limit → CKAsset; known sync reliability issues → consider syncing text+thumbnail only, treat full images as device-local; iCloud quota = user's storage → sync cap policy. |
| Distribution / discovery (CEO) | Phase 9 launch + open-source from day 1. |
| Differentiation asserted, not built (CEO + Design) | Invest in Favorites/Pinboards UX + per-type previews + the Mímir capture-pulse motif as the ownable signatures; spec states/metrics/a11y (§10). |
| Sustainability | Open-source → contributor maintenance (the chosen answer). |

---

## 8. Testing

- **Unit:** representation precedence; ignore rules (all four nspasteboard markers + PW-manager blocklist); dedup hashing incl. images; **pruning exempts favorites/pinned**; importer row mapping; **pasteboard-race discard** (fake pasteboard that mutates `changeCount` mid-read); **CloudKit schema validity** (`initializeCloudKitSchema` with sync off).
- **Integration:** palette keyboard flow (type → ↑↓ → ⏎), **focus-return before ⌘V**, Esc dismiss, ⌘1–9.
- **Manual capture/paste matrix:** copy from Safari, Notes, Xcode, Finder, Preview, Mail, Terminal, VS Code, Figma, Numbers × {plain, RTF, HTML, PNG/TIFF, multi-file, URL+title, hex color, code}; paste into the same set incl. apps that reject synthetic paste; password managers ignored; auto-paste-denied → manual fallback; **import against a real CopyClip DB on macOS 13/14/15**; login-item `.requiresApproval`; >50MB image cap; rapid-copy coalescing.

## 9. Tooling to install (Phase 0)
`brew install xcodegen swiftlint swiftformat xcbeautify create-dmg` — project generation, lint/format, readable build logs, DMG packaging. Sparkle via SPM. Homebrew Cask tap when we publish.

## 10. Design follow-ups (from the design review — fold into the relevant phases)
- **Spec the missing states:** empty first-run (the literal first screen), no-results → "Create snippet from this text", recording-paused ambient indicator, paste-failed fallback toast, very-large clip, many pinboards.
- **Add metrics/layout:** window W×H, ~60/40 list/preview split + min width, row height, type scale, motion durations + curves, and the **reduce-transparency / reduce-motion fallbacks**.
- **Interaction fixes:** favorite = **⌘D** (⌘F collides with Find); specify Esc (two-stage: clear → close), scope-switch (⇥), actions menu (⌘K), ⌘1–9 = Nth *visible* row with number badges, ⌫ delete **with undo**; per-row hover actions + right-click menu for mouse discovery.
- **Accessibility is first-class, not Phase-7:** VoiceOver labels per row, visible focus order across search/list/preview, WCAG AA contrast over glass, solid fallback under Reduce Transparency, Dynamic Type.
- **Differentiation:** design the Pinboards manager and per-type previews with the same rigor as the palette — that's where Mimer beats Paste; the palette chrome only ties Raycast.
