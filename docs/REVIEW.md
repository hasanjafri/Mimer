# Mimer — Plan Review Report (`/autoplan`)

*June 2026. Pressure-tested `PLAN.md` v1 across three lenses — CEO/strategy, design, engineering — each with an independent review agent. (Codex CLI not installed, so the "second voice" ran as independent Claude review agents rather than dual-model.) Findings, the gate decisions, and the resulting changes to `PLAN.md` are below.*

---

## Consensus scorecard

| Lens | Verdict | Headline |
|---|---|---|
| CEO / strategy | Concerns → Bad | No distribution plan; "free + no revenue" sustainability unexamined; macOS 26 built-in = demand-destruction; v1 over-scoped |
| Design | Mixed | Strong positioning; weak design *spec* — states 2/10, specificity 3/10, accessibility 1/10; differentiation asserted, not built |
| Engineering | Sound (with fixes) | Architecture correct; 2 factual errors (import, auto-paste); CloudKit constraints incomplete; capture race unhandled; spikes sequenced too late |

**Cross-phase themes (independent agreement = high-confidence):**
1. **Differentiation is asserted, not built.** "Beautiful/Liquid Glass" is the commodity OS look; the one truly differentiating surface (permanent Favorites/Pinboards) was the least designed.
2. **Copy-then-⌘V should be the baseline hero** (auto-paste as an enhancement) — later resolved favorably by going direct/non-sandboxed, which makes auto-paste a clean first-class feature.

---

## Decisions at the approval gate

| # | Question | Your choice | Classification |
|---|----------|-------------|----------------|
| D1 | Go-to-market | **Open-source + direct-download first** (Homebrew; MAS later) | User challenge — accepted the change (was MAS-first/closed) |
| D2 | Sustainability | **Completely free forever** (no Pro tier) | Original kept; coherent with open-source (contributor maintenance) |
| D3 | v1 scope | **Keep the full 8-phase v1** | Original kept; eng *sequencing* advice still applied |

**Why D1 matters most:** open-source + direct/non-sandboxed neutralizes the two biggest engineering hazards at once — auto-paste's App Review 2.4.5 risk (no MAS review) and import's competitor-container review optics — and makes auto-paste a clean first-class v1 feature. It's also the actual growth engine. D2 + open-source answers the sustainability concern (contributors share maintenance).

---

## Engineering findings (the actionable corrections)

**Factual errors fixed in `PLAN.md`:**
- **W1 — CopyClip import was broken.** Single-file security-scoped bookmark doesn't cover `-wal`/`-shm`; live-WAL read is unsafe (`SQLITE_BUSY`/corruption); macOS 14+ adds a non-suppressible cross-container consent prompt. → Fix: folder grant + `VACUUM INTO` clean copy + read-only.
- **W2 — Auto-paste mischaracterized.** It's `kTCCServicePostEvent` (not Accessibility AX, not AppleScript), is sandbox-compatible (Apple DTS; Maccy ships it), and the only risk was App Review 2.4.5. → Fix: corrected wording; first-class on direct.

**Other high/medium fixes folded in:**
- **B1** Palette focus model needs `canBecomeKey=true`, `.nonactivatingPanel`, `makeKey` after positioning, no `NSApp.activate`, focus-return **before** ⌘V (the #1 auto-paste bug). → Spike A, Phase 0.
- **D1(model)** CloudKit constraints were incomplete: every relationship needs an inverse; no `Deny` delete rules; **no `Ordered` relationships** (Pinboard reorder uses `sortIndex`); app-enforced dedup. → Added to data model.
- **D2/D3(storage)** Large blobs over CloudKit have real reliability limits (v2); in-memory fuzzy is fine only if blobs aren't faulted into the search path; FTS5 ≠ fuzzy. → Noted.
- **E** Capture: 500ms (not 200ms); ignore `RestoredType` + PW-manager blocklist; representation precedence + plain-text fallback; content-hash dedup; **race-safe** changeCount re-read; off-main capture. → Added.
- **F** Failure modes: `SMAppService.requiresApproval`; iCloud-enable-later is a **real migration**, not a flag-flip (keep model valid + schema test); no false "pasted" confirmation. → Added.
- **G** Sequencing: pull two spikes (auto-paste/focus, import) into Phase 0; full scope kept with a 1.1 release-valve (Tags / multi-pinboard / import).

---

## Design findings (folded into PLAN §10 + relevant phases)
- Specify the missing states (empty first-run, no-results→create-snippet, paused indicator, paste-failed, large clip, many pinboards).
- Add real metrics/layout (window size, ~60/40 split, row height, type scale, motion + reduce-motion/transparency fallbacks).
- `⌘F` collides with Find → favorite = **⌘D**; specify Esc (two-stage), scope-switch (⇥), actions menu (⌘K), ⌘1–9 = Nth visible row + badges, ⌫ delete with undo; mouse discovery (hover actions + right-click).
- Accessibility is first-class, not a Phase-7 footnote.
- Build differentiation into Favorites/Pinboards + per-type previews + the Mímir capture-pulse motif (the palette chrome only ties Raycast).

---

## CEO findings (disposition)
- **Distribution gap** → added **Phase 9 — Launch & distribution** + open-source from day 1. ✅
- **Sustainability** → free + open-source (contributors). ✅
- **OS built-in = demand-destruction** → reframe around images/files + organize/reuse + private sync (the OS won't do these). ✅ (positioning)
- **Aesthetics ≠ moat** → differentiation via Favorites/previews/motion, not "pretty." ✅
- **Scope too big** → user kept full v1; mitigated with front-loaded spikes + 1.1 release-valve. ⚖️ (user's call)
- **Sync is the moat, deferred** → kept local-only v1 (user's scope choice); sync is the first post-1.0 headline. ⚖️

---

## Deferred / release-valve (1.1 if 1.0 stretches)
Tags (keep simple Favorites for 1.0) · multi-pinboard organization · CopyClip import · color/code content types.

## Restore point
Pre-review `PLAN.md` is preserved at `~/.gstack/projects/Mimer/main-autoplan-restore-*.md`.
