# CI/CD

Two GitHub Actions workflows, plus branch protection on `main`.

## CI — `.github/workflows/ci.yml`

Runs on every **PR to `main`** and every **push to `main`**:

1. `xcodegen generate` (the `.xcodeproj` is git-ignored, generated from `project.yml`)
2. Debug **build + test** — the full XCTest suite (28 tests)
3. **Release build** — guards that `DebugBridge` (`#if DEBUG` only) never leaks into
   the shipping configuration

The job is named **`Build & test`** and is a **required status check** on `main`
(see Branch protection). If you rename the job, update the protection rule to match.

## Branch protection on `main`

Configured via the API (it's repo settings, not a file in the repo):

- **Require a pull request before merging** — contributors work on branches and open
  PRs; they cannot push to `main` directly.
- **0 required approvals** — a solo maintainer can't approve their own PR, so requiring
  approvals would block you. CI is the gate instead.
- **Require `Build & test`** to pass before merging.
- **Admins are not enforced** (`enforce_admins: false`) — you (the owner) can push
  directly to `main` and bypass when needed; nobody else can.
- **No force-pushes, no deletion** of `main`.

To re-apply after changes:

```sh
gh api -X PUT repos/hasanjafri/Mimer/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": { "strict": false, "contexts": ["Build & test"] },
  "enforce_admins": false,
  "required_pull_request_reviews": { "required_approving_review_count": 0, "dismiss_stale_reviews": false },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

## Release — `.github/workflows/release.yml`

**Owner-only, manual.** Actions ▸ Release ▸ *Run workflow*:

- **bump**: `patch` / `minor` / `major` — the next version is computed from the current
  `MARKETING_VERSION` in `project.yml`.
- **dry_run**: build + sign + notarize + package + sign the appcast, but **do not**
  publish, commit, tag, or bump the tap. Run this first the first time.

What a real run does, end to end:

1. Recreates the signing keychain from secrets, then runs `scripts/release.sh <version>`
   unchanged (archive → Developer ID sign → notarize → staple → DMG → sign the Sparkle
   `appcast.xml`).
2. Bumps `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in `project.yml`.
3. Commits the bump + signed `appcast.xml` to `main` and tags `vX.Y.Z`
   (pushed as you via `RELEASE_TOKEN`, which is why it's allowed past branch protection).
4. Creates the **GitHub Release** with the DMG attached.
5. Bumps **`hasanjafri/homebrew-tap`** `Casks/mimer.rb` (version + sha256).

Result: available via `brew upgrade --cask mimer`, the GitHub Releases page, and
Sparkle in-app auto-update.

Only the repository owner can run it (`if: github.actor == github.repository_owner`),
and triggering `workflow_dispatch` already requires write access — a merged contributor
cannot cut a release.

### Required secrets

Settings ▸ Secrets and variables ▸ Actions:

| secret | what it is | how to get it |
| --- | --- | --- |
| `DEVELOPER_ID_CERT_P12_BASE64` | base64 of your Developer ID Application cert (.p12) | export from Keychain Access, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_CERT_PASSWORD` | password you set on that .p12 export | — |
| `KEYCHAIN_PASSWORD` | any string; password for the throwaway CI keychain | make one up |
| `NOTARY_APPLE_ID` | Apple ID email for notarization | your Apple ID |
| `NOTARY_TEAM_ID` | 10-char Developer Team ID | `security find-identity -v -p codesigning` |
| `NOTARY_PASSWORD` | app-specific password | account.apple.com ▸ Sign-In and Security ▸ App-Specific Passwords |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key for the appcast | export the key you already have: `generate_keys -x key.txt`, paste the file contents (the public half is `SUPublicEDKey` in `project.yml`) |
| `RELEASE_TOKEN` | fine-grained PAT, **Contents: read/write** on both `Mimer` and `homebrew-tap` | github.com ▸ Settings ▸ Developer settings ▸ Fine-grained tokens |

`GITHUB_TOKEN` (built in) creates the Release; everything that touches protected `main`
or the tap repo uses `RELEASE_TOKEN`.

> First time: run with **dry_run = true** to validate signing/notarization/appcast before
> cutting a real release.
