# Mimer — Forward Review & Decisions (working v0, June 2026)

Reviewed the **shipped v0** (not just the plan) via `/autoplan`: four independent Claude lenses (CEO, DevEx, Design, Eng) + two **Codex cross-model** passes (CEO, DevEx). Findings were unanimous and code-grounded.

## Verdict
As shipped, Mimer is **undifferentiated vs free Maccy + the free macOS 26 built-in** — "a worse Maccy." The doc's differentiators (rich types, pinboards, preview, fuzzy) are **specced but unbuilt**; search is plain substring; favorites are sort-to-top; the headline **auto-paste flow is broken** (the permission ask is buried inside the first paste, which then silently fails).

## Decisions (approved)
1. **Positioning: developer-first.** Optimize the next ~10 features for developers.
2. **Sync: deferred; stop pre-paying the CloudKit "tax."** Shape the model for the dev features (`kind`, `contentHash`, blobs), not for CloudKit constraints. Sync becomes real, scoped work later *if* validated. (The "cheap flag-flip later" assumption was already false in the code.)
3. **Monetization: free + OSS now, but reserve an optional one-time Pro lever** (no subscription) for later power features — not $0-locked.
4. **Build order: foundation refactors → parity basics → the wedge.**

## The wedge (durable differentiation — OS-proof, Maccy lacks)
**Code/JSON-aware clips + transforms** (paste-as-plain, JSON pretty/minify, trim, base64, URL-encode, case) · **paste-stack** (queue N, paste in order) · **snippets** (authored permanent clips).

---

## Ranked next work

### A. Foundation refactors — DO FIRST (≈4 files, before features)
1. **Stop faulting whole objects/blobs into the list path.** `ClipStore.refresh()` + search → lightweight projection fetch (`propertiesToFetch`/dictionary). `prune()` → `NSBatchDeleteRequest` (no fetch-all per insert). Add **`kind: Int16`** (+ `ClipKind`) and **`contentHash`** columns now; `ClipItem` carries `kind` + optional payload. Cap `historyLimit` with a sane max.
2. **Swift 6 language mode** (`project.yml` 5.0 → 6.0). Make `onCapture` `@Sendable`; make the capture→store boundary an explicit `@MainActor` hop **before** moving capture off-main (write the safe version first). Add the off-main extraction seam for when images land.
3. **Implement the two missing capture guards:** changeCount re-read (race discard) + a `RestoredType`/self-paste marker stamped by `Paster.copyToPasteboard` and ignored by the monitor. Add the mandated unit tests (race-discard, self-paste ignore).
   - Close the comment↔code gap: the "CloudKit-valid / off-main / race-safe" comments describe a system that doesn't exist yet — fix or correct them. Drop the `initializeCloudKitSchema` test (sync deferred).
   - Add a release-build guard so the `#if DEBUG` `DebugBridge` can never ship.

### B. Parity basics — reach "as good as Maccy"
Fuzzy (subsequence) search over the projection · **paste-as-plain `⌥⏎`** · **`⌘1–9`** quick-paste + row badges · **`⌫` delete** (`ClipStore.delete` exists, unused) + undo · **onboarding** (welcome + hotkey teach + contextual PostEvent grant *while the palette is key*; honest "Copied — press ⌘V" fallback, never a false "Pasted") · **launch-at-login** (`SMAppService`) · **per-app exclusions + pause** + menu-bar paused indicator + password-manager **bundle blocklist** · **favorites separation** (Recents/Favorites/All scope or a section, with a leading signature-accent indicator) · remove the "text only · more soon" string.

### C. The wedge — differentiate
Code/syntax-aware clips (language/JSON detect, monospace, transforms via a `⌘K` actions menu) → **snippets** (authored clips, `kind = .snippet`, built on the never-prune favorites infra) → **paste-stack**.

### D. Parity-not-wedge (after the wedge)
Images/files — the **preview pane** earns its space here; add a typed-glyph rail. Don't over-invest (it's parity with Maccy/Paste, not a switch reason).

### E. In parallel from DAY ONE (not "Phase 9 last")
Public GitHub README with GIFs · Homebrew Cask · Sparkle auto-update. Distribution is a continuous loop, not a launch-day spike.

---

## Design fixes (fold into the above)
- Favorites: real separation + a **signature indigo/teal "forever" accent** (kill the default yellow star); leading indicator, not a far-right caption star.
- **Trust trio:** delete + undo + a visible recording-pause toggle/indicator.
- **Distinctiveness:** a "captured" pulse on the menu-bar icon; typed-glyph rail; reconcile `DesignSystem` token drift (PaletteView ignores the declared tokens).
- **Accessibility (not Phase-7):** VoiceOver labels per row, Reduce-Transparency solid fallback, Dynamic Type, lift the keyboard-hint text out of caption2/tertiary contrast.
- **Preview pane:** build it for content a single row can't represent (long text + every rich type), not an always-on empty 40% over text-only data.

## Method note
Codex (cross-model) independently reached the same core conclusion as the Claude lenses — v0 is narrower than its roadmap and hasn't built the differentiators needed to escape Maccy/the OS built-in — so the consensus is genuinely cross-model. Full per-lens detail lives in the review-agent transcripts; this file is the actionable distillation.
