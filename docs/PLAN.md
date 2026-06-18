# Mimer — Engineering Plan & Roadmap

*Native macOS clipboard manager. This plan reflects the locked product decisions and the real constraints of a sandboxed Mac App Store app.*

---

## 1. Locked decisions

| Decision | Choice | Consequence |
|---|---|---|
| **Monetization** | **Completely free** (no paywall; open-source optional) | No IAP/licensing code. Strong "private & free" story. Can MIT-license like Maccy. |
| **Distribution** | **Mac App Store first** | App Sandbox **on**. Some constraints (esp. auto-paste & import — see §3). Direct/Sparkle build can come later. |
| **Sync & scope** | **Local-only Mac v1, sync-ready** | Ship fast & private; design the data layer now so **iCloud (CloudKit) drops in for v2** with minimal rework. |

---

## 2. Tech stack

| Concern | Choice | Why |
|---|---|---|
| Language / tooling | **Swift 6, Xcode 26** | Already installed; current. |
| UI | **SwiftUI** views + thin **AppKit** plumbing | Modern UI; AppKit only where SwiftUI can't reach (floating panel, status item). |
| Menu-bar item | **`MenuBarExtra`** (SwiftUI) | Native menu-bar companion with a SwiftUI dropdown. |
| Command palette | **`NSPanel`** (nonactivating, floating) hosting SwiftUI via `NSHostingView` | A Spotlight/Raycast-style centered panel that can take key focus without fully activating the app — `MenuBarExtra` can't do this. |
| App lifecycle | SwiftUI `App` + `NSApplicationDelegateAdaptor` | Agent app (`LSUIElement`), no dock icon. |
| Global hotkey | **`KeyboardShortcuts`** (Sindre Sorhus, SPM) | De-facto standard; **sandbox/MAS-safe**; gives a user-recordable shortcut control in Settings. Avoids raw Carbon. |
| Storage | **Core Data + `NSPersistentCloudKitContainer`** | Mature; handles large stores + **external binary** image/file blobs; **flip a flag to enable iCloud sync** later. (SwiftData is the lighter alternative but weaker for big blobs today.) |
| Search | In-memory fuzzy match over recent fetch (v1); SQLite **FTS5** if histories get large | Fast and simple at expected scale (thousands of items). |
| Launch at login | **`SMAppService`** (macOS 13+) | Sandbox-friendly, no helper hacks. |
| Clipboard capture | **`NSPasteboard` + `changeCount` polling** | NSPasteboard has no change notification; polling is the standard, sandbox-legal approach. |

---

## 3. Sandbox & permissions reality (the parts that bite)

These are the constraints that determine the design — getting them right up front avoids rework:

1. **Reading the clipboard** — `NSPasteboard.general` is fully readable in the sandbox, **no entitlement needed**. ✓
2. **Global hotkey & launch-at-login** — both work sandboxed via `KeyboardShortcuts` and `SMAppService`. ✓
3. **Auto-paste (synthesizing ⌘V)** — posting a key event to the frontmost app needs **Accessibility (TCC) permission**, which is a *gray area for App Store review* in a sandboxed app. **Plan:**
   - **Baseline (always works):** selecting a clip places it on the pasteboard and closes the palette; the user pastes with ⌘V.
   - **Optional auto-paste:** offered behind an explicit Accessibility-permission prompt, with graceful fallback to the baseline if denied/unavailable.
   - **De-risk early:** validate the auto-paste path against App Review in the first TestFlight; if MAS rejects it, keep auto-paste for a later **direct-distribution** build and ship baseline on MAS.
4. **Import from CopyClip** — the sandbox **blocks silently reading another app's container**. So import is a **guided `NSOpenPanel`**: we point the user at `…/Containers/com.fiplab.clipboard/…/copyclip.sqlite`, they grant access (security-scoped bookmark), we read & map the rows. Sandbox-legal and honest.
5. **Privacy nutrition label** — we collect **nothing**; label = *"Data Not Collected."* This is a marketing asset, not just compliance.
6. **CloudKit-readiness now** — model designed CloudKit-compatible from day one (all attributes optional or defaulted, no unique constraints, optional relationships) even though sync ships later.

**Entitlements (v1):** App Sandbox; `com.apple.security.files.user-selected.read-only` (import); iCloud/CloudKit entitlement added when sync ships.

---

## 4. Architecture

```
MimerApp (SwiftUI App, LSUIElement)
├── AppDelegate            – sets up panel + hotkey + monitor lifecycle
├── MenuBarExtra           → MenuBarView (recents, favorites, pause, settings)
├── PalettePanel (NSPanel) → PaletteView  (search · list · live preview)
├── Settings scene         → General / Privacy / Appearance / About
│
├── Core
│   ├── ClipboardMonitor   – changeCount polling, type extraction, ignore rules
│   ├── Paster             – set pasteboard (+ optional Accessibility auto-paste)
│   ├── HotkeyManager      – KeyboardShortcuts wiring
│   └── LaunchAtLogin      – SMAppService
│
├── Data (Core Data, CloudKit-ready)
│   ├── ClipStore          – CRUD, search, favorites, pinboards
│   └── Models             – Clip, ClipKind, Pinboard, Tag
│
├── Features
│   ├── Onboarding         – welcome · hotkey · permissions · import
│   └── CopyClipImporter   – NSOpenPanel → read SQLite → map → insert
│
└── DesignSystem           – colors, type, materials, reusable views/icons
```

**Data model (v1):**
- `Clip` — `id`, `kind` (text/richText/image/file/link/color/code), `plainText`, `richData` (RTF/HTML, external binary), `imageData` (external binary), `thumbnailData`, `fileURLs`, `sourceAppBundleID`, `sourceAppName`, `createdAt`, `lastUsedAt`, `isFavorite`, `pinOrder`, `pinboard` (rel), `tags` (rel).
- `Pinboard` — `id`, `name`, `symbol`, `sortIndex`, `clips` (rel).
- `Tag` — `id`, `name`, `clips` (rel).
- Rolling history is pruned by a configurable cap; **favorites/pinboard clips are exempt from pruning** (the "saved forever" guarantee).

---

## 5. Roadmap (phased, effort = S/M/L)

**Phase 0 — Scaffold** *(S)*: Xcode project (SwiftUI macOS app, `LSUIElement`, App Sandbox), SPM deps (`KeyboardShortcuts`), entitlements, menu-bar agent skeleton, DesignSystem stub, CI-friendly structure, commit.

**Phase 1 — Clipboard engine + history** *(M)*: `ClipboardMonitor` (poll + dedupe + ignore transient/concealed types), Core Data store, capture text first, menu-bar dropdown listing recents, click-to-copy-back. *Milestone: a working, private clipboard history.*

**Phase 2 — Command palette** *(L)*: `NSPanel` palette, global hotkey, instant fuzzy search, list + live preview, full keyboard nav, ⌘1–9 quick paste, paste / paste-as-plain. *Milestone: the headline UX.*

**Phase 3 — Favorites & Pinboards** *(M)*: one-key favorite, never-expire guarantee, pinboards/tags, organize/reorder UI. *Milestone: the "saved forever" promise — the thing you asked for, done right.*

**Phase 4 — Rich content types** *(M)*: images, files, links (title/favicon), colors (swatch), code (mono + optional highlight) with tailored previews + actions.

**Phase 5 — Privacy & Settings** *(M)*: excluded-apps list, pause recording, ignore rules, history-size cap, appearance, launch-at-login, all Settings panes.

**Phase 6 — Onboarding + CopyClip import** *(M)*: first-run flow (hotkey, permissions explained honestly), guided import of existing CopyClip SQLite history.

**Phase 7 — Polish & QA** *(M)*: motion, empty states, full accessibility (VoiceOver/keyboard), performance pass (10k+ clips, image memory), custom app + menu-bar icon.

**Phase 8 — Ship to Mac App Store** *(M)*: App Store Connect, sandbox/entitlement audit, screenshots, "Data Not Collected" privacy label, TestFlight (validate auto-paste with review), submit.

**v2 and beyond:** iCloud sync (enable CloudKit on the existing container) · snippets/templates · iOS/iPad companion with keyboard · OCR on images · paste stacks · smart actions.

---

## 6. Key risks & mitigations

| Risk | Mitigation |
|---|---|
| Auto-paste rejected by App Review | Ship baseline (manual ⌘V) on MAS; auto-paste optional via Accessibility; reserve full version for a direct build if needed. |
| Polling CPU/battery cost | 0.2–0.5s interval, cheap `changeCount` check, throttle on battery/idle. |
| Capturing passwords | Honor `org.nspasteboard.ConcealedType` / `TransientType` / `AutoGeneratedType` + password-manager markers; user exclusions. |
| Image clips bloating the store | External binary storage, thumbnails for lists, size cap, prune non-favorites. |
| Painting into a CloudKit corner later | Model designed CloudKit-compatible from day one. |
| SwiftData vs Core Data regret | Chose Core Data for proven blob + CloudKit handling. |

---

## 7. Testing
- **Unit:** type extraction, ignore rules, dedupe, pruning-exempts-favorites, importer mapping.
- **UI/integration:** palette keyboard flows, paste correctness, hotkey.
- **Manual matrix:** copy from Safari/Notes/Xcode/Finder/Preview (text, rich, image, file, link); password managers ignored.

## 8. Tooling to install (when we start coding)
- `brew install swiftlint swiftformat xcbeautify` — lint/format + readable build logs (optional but recommended).
- `create-dmg` / `fastlane` — only if/when we add **direct distribution**; not needed for MAS-first.

## 9. gstack skills to use along the way
- **`/plan-eng-review`, `/plan-design-review`** (or **`/autoplan`**) — pressure-test *this plan* before we build.
- **`/design-review`** — designer's-eye QA on the UI as it comes together.
- **`/ship`** — release workflow when we cut builds.
- **ios-\*** skills — when the iOS companion lands in v2.
