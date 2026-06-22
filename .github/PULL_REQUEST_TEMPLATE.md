<!-- Thanks for the PR! Keep it to one logical change. -->

## What & why
<!-- What does this change, and what problem does it solve? -->

## How to test
<!-- Steps a reviewer can follow, plus what you verified. -->

## Checklist
- [ ] `xcodegen generate` then `xcodebuild … test` passes locally (CI runs the same).
- [ ] Added/updated tests for the change (regression test for a bug; both branches for a new conditional).
- [ ] Updated `README.md` / `CLAUDE.md` / `CHANGELOG.md` if affected.
- [ ] No hand-edits to the generated `.xcodeproj` / `Info.plist` (changed `project.yml` instead).
- [ ] Branched off `main`; one logical change.
