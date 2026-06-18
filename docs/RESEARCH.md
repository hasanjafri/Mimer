# Mimer — Research & Market Analysis

*Compiled June 2026. Sources: live web research + a local teardown of CopyClip running on the target machine.*

---

## 1. Executive summary

The Mac clipboard-manager market is busy but **polarized**, leaving a clear gap:

- **Cheap/free options are dated or minimal.** CopyClip 2 ($7.99) is *text-only* on an aging AppKit UI. Maccy (free) is beloved for privacy and speed but is deliberately spartan. Flycut is abandoned. macOS 26 now ships a built-in history, but it's text-only and items expire.
- **The polished option is a subscription.** Paste is gorgeous and syncs via iCloud, but it's **$29.99/year** and stores history in the cloud by default — a dealbreaker for privacy-conscious users.
- **Nobody owns "beautiful + private + images/files + permanent favorites + fair one-time/free price."** The closest, QuietClip ($8.99), is explicitly criticized for a UI that "lacks visual distinctiveness."

**The wedge for Mimer:** *Maccy's privacy and price + Paste's polish + images/files + permanent organized Favorites + a Raycast-grade command palette — local-first, no subscription, and the best-looking native app in the category.*

---

## 2. How this was researched

- **Local teardown** of `CopyClip.app` (v1) installed and running on the machine: bundle inspection (`defaults`, `otool`, `lipo`, `codesign`), sandbox container, and storage format.
- **Web research** across the Mac App Store, FIPLAB's site, the Maccy GitHub repo, and 2026 "best clipboard manager" comparison articles (sources in §11).

---

## 3. CopyClip v1 (free) — local teardown

What the installed app actually is, confirmed on-machine:

| Attribute | Finding |
|-----------|---------|
| Version | 1.9.86 (`com.fiplab.clipboard`), developer FIPLAB (Team `VM4H2VWS56`) |
| Distribution | **Mac App Store, sandboxed** (`_MASReceipt` present) |
| UI tech | **Legacy AppKit + `.nib`** files — an `NSTableView` popup window + 3 plain preference tabs (General / Exceptions / About) |
| Hotkey | **Carbon** `RegisterEventHotKey` (the legacy global-hotkey API) |
| Storage | **Plain SQLite** DB (`Application Support/CopyClip/copyclip.sqlite`, ~2.6 MB of history in the WAL) |
| Localization | **English only** |
| Binary | Universal (x86_64 + arm64) |
| **Capacity** | **Saves only ~80 items; shows 20 in the dropdown** |

**Takeaways:**
1. The free tier is *deliberately crippled* (80 items) to upsell CopyClip 2.
2. The stack is dated (nib-based AppKit, Carbon) — explains the stale look/feel. Easy to leapfrog.
3. Because storage is a **readable SQLite file**, Mimer can offer a one-click **"Import your CopyClip history"** onboarding step.

---

## 4. CopyClip 2 (paid) — the upgrade

| Attribute | Finding |
|-----------|---------|
| Price | **$7.99 USD** (~€8.99) one-time, Mac App Store |
| Version | 3.993, **actively updated** (last update ~1 day before research); macOS 11.5+ |
| Ratings | "Hasn't received enough ratings to display an overview" (low review volume) |
| Engine | Native **AppKit** (explicitly "not Electron") |

**Marketed features:** up to **9,999 _text_ clippings**; paste with original formatting **or** as plain text; instant search bar; **⌘1–9 / ⌘0** quick-paste; **pin** clips to top (recently improved to preserve pin order); auto-exclude passwords/sensitive fields; **10 color themes**; bulk edit/delete; Quick Look preview; tracks the source app; pause recording ("private mode"); app exclusions; history limits.

**Critical limitation:** **text-only — no images or files.** Reviewers note it "feels dated" and that a menu-bar list is slower than a keyboard-driven panel. The "favourite saved forever" feature observed = its basic **pin-to-top**.

### CopyClip v1 vs v2

| Capability | v1 (Free) | v2 ($7.99) |
|---|---|---|
| Items stored | ~80 (20 shown) | up to 9,999 |
| Search | ✗ (menu only) | ✓ |
| Pin / "favorites" | ✗ | ✓ (pin to top) |
| Paste as plain text | ✗ | ✓ |
| ⌘1–9 quick paste | ✗ | ✓ |
| Themes | ✗ | ✓ (10) |
| Images / files | ✗ | ✗ |
| Sync | ✗ | ✗ |

---

## 5. The competitive landscape

| App | Price | Images/Files | Sync | Search | Favorites/Pins | Snippets | Polish | Privacy |
|---|---|---|---|---|---|---|---|---|
| **CopyClip 2** | $7.99 once | ✗ | ✗ | ✓ | ✓ pin | ✗ | Dated (10 themes) | Local, excl. passwords |
| **Maccy** (OSS) | Free | text-focused¹ | ✗ | ✓ fuzzy | ✓ pins | ✗ | Minimal | Local (excellent) |
| **Paste** | **$29.99/yr** | ✓ | ✓ iCloud | ✓ | ✓ pinboards | partial | **Excellent** | ⚠ Cloud-by-default |
| **Raycast** | Free / $8-mo Pro | ✓ images | Pro only | ✓ | ✓ | ✓ | Good | Local/cloud |
| **Alfred** | ~$34 once (Powerpack) | ✓ | ✗ | ✓ | partial | ✓ | Dated | Local |
| **Pastebot** | $12.99 once | ✓ | ✗ | ✓ | ✓ | ✓ filters/pipelines | Good | Local |
| **QuietClip** | $8.99 once | ✓ | ✗ | ✓ | ✓ | ✗ | "lacks distinctiveness" | Local |
| **PastePal** | ~$10–15 once | ✓ | ✓ iCloud | ✓ | ✓ | ✓ | OK | Cloud opt-in |
| **Flycut** (OSS) | Free | ✗ | ✗ | ~ | ~ | ✗ | Abandoned/dated | Local |
| **macOS 26 built-in** | Free | ✗ | ✗ | ✗ | ✗ | ✗ | Native | Local (expires) |

¹ *Maccy is primarily text-focused with a deliberately minimal UI; image handling is limited and it has no sync or iOS app.*

---

## 6. Pricing landscape

- **Free / open-source:** Maccy, Flycut, Raycast (free tier), macOS built-in.
- **One-time purchase:** CopyClip 2 ($7.99), QuietClip ($8.99), PastePal (~$10–15), Pastebot ($12.99), Alfred Powerpack (~$34).
- **Subscription:** Paste ($29.99/yr), Raycast Pro ($8/mo for sync/AI).

**Signal:** the market clearly rewards **one-time pricing**; the loudest complaint about the category leader (Paste) is its **subscription creep and lack of a one-time option**.

---

## 7. The new baseline: macOS 26 built-in clipboard history

macOS 26 (Tahoe) now ships a native clipboard history. It is **free and private but bare**: text-only, **items expire**, no pins, no search, no app exclusions. Any paid/installed manager must now *clearly* beat it — which means **images & files, permanent favorites, search, organization, and sync** are table stakes for differentiation, not nice-to-haves.

---

## 8. What users actually want (synthesized & ranked)

1. **Privacy / local-first** — don't ship my clipboard to the cloud; auto-ignore passwords. *(Maccy's entire appeal.)*
2. **No subscription** — one-time or free; people actively resent Paste's $30/yr.
3. **Images + files + rich text**, not just plain text. *(CopyClip, Maccy, Flycut, OS built-in all fail here.)*
4. **Beautiful, fast, keyboard-first UX** — a Raycast/Spotlight-style command palette beats a clunky menu list.
5. **Permanent, organized Favorites** — "saved forever," ideally with folders/tags. *(Your headline ask.)*
6. **Optional cross-device sync** (Mac↔Mac, and especially iPhone) *without* a privacy compromise — a recurring unmet need.
7. **Instant fuzzy search.**
8. **Snippets / templates** (canned text).
9. **App exclusions, pause, sensitive-data handling.**
10. **Quick paste (⌘1–9), paste-as-plain-text, paste stack**, source-app + timestamp metadata.

---

## 9. Gaps & opportunities → Mimer's wedge

| Gap in the market | How Mimer wins |
|---|---|
| Cheap apps are ugly/dated (CopyClip 2, QuietClip) | **Best-in-class native macOS 26 design** + command palette |
| Free apps are minimal (Maccy, Flycut, OS built-in) | **Images/files, favorites, search, polish** while staying fast |
| Polished app is a cloud subscription (Paste) | **Local-first, no subscription**, optional *end-to-end* sync later |
| "Favorites" everywhere = a basic pin | **Permanent Favorites + Pinboards/tags** that never expire |
| Nobody nails Mac→iPhone without a subscription | Architect for **optional iCloud/CloudKit sync** (Mac first, iOS later) |
| Switching cost from CopyClip | **One-click import** of the user's existing CopyClip SQLite history |

**Positioning one-liner:** *"Mimer is the clipboard manager Maccy users wish looked like Paste — private, gorgeous, handles images and files, keeps your favorites forever, and never charges a subscription."*

---

## 10. Open product decisions (drive the engineering plan)

1. **Monetization** — free / open-source vs generous-free + one-time Pro vs paid one-time.
2. **Distribution** — Mac App Store (sandboxed) vs direct (notarized + Sparkle) vs both.
3. **Sync & platform scope** — local-only v1 vs iCloud sync vs full Mac + iOS.

*(These are surfaced to the user before `PLAN.md` is finalized.)*

---

## 11. Sources

- CopyClip 2 — FIPLAB: https://fiplab.com/apps/copyclip-for-mac
- CopyClip 2 — Mac App Store: https://apps.apple.com/us/app/copyclip-2-clipboard-manager/id1020812363
- CopyClip (free) — Mac App Store: https://apps.apple.com/us/app/copyclip-clipboard-history/id595191960
- Maccy — GitHub: https://github.com/p0deje/Maccy
- Clipboard Manager Comparison (2026): https://quietclip.app/blog/clipboard-manager-comparison/
- Paste alternatives (2026): https://www.onetapapp.co/OneTap-blog-posts/paste-app-alternatives-7-best-clipboard-managers-for-mac-in-2026
- Pastebot — Tapbots: https://tapbots.com/pastebot/ · https://apps.apple.com/us/app/pastebot/id1179623856
- PastePal: https://pastepal.macupdate.com/
- Best clipboard managers — Zapier: https://zapier.com/blog/best-clipboard-managers/
- Local teardown of `CopyClip.app` v1.9.86 (on-machine inspection)
