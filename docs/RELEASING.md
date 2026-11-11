# Releasing Skitcho

Releases are built, signed, notarized and published by `.github/workflows/release.yml`
when a `v*` tag is pushed; only the first release is built and published by hand (see
[The first release](#the-first-release)). Each release ships `Skitcho-X.Y.Z.dmg` (a compressed disk image with
`Skitcho.app` and an `Applications` link for drag-to-install) and `appcast.xml`. This page describes
the one-time maintainer setup and the per-release flow. No secret value ever belongs in the repository.

## One-time setup

### 1. Sparkle update signing key

Sparkle verifies updates with an EdDSA key pair. The maintainer key lives in the login Keychain
under the account `skitcho`. Create it once on a trusted Mac:

```bash
swift build --arch arm64   # fetches the Sparkle artifact bundle
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account skitcho
```

`generate_keys` stores the private key in your login Keychain and prints the public key.
Running it again with the same `--account` only prints the existing public key.

- Put the printed **public** key in the repository variable `SPARKLE_PUBLIC_ED_KEY`
  (Settings, Secrets and variables, Actions, Variables). It is embedded in the app as `SUPublicEDKey`.
- Export the **private** key to a private temporary file **outside the repository**, store it as the
  `release` environment secret `SPARKLE_ED_PRIVATE_KEY`, then delete the file:

  ```bash
  (
    umask 077
    tmp="$(mktemp -d)"
    .build/artifacts/sparkle/Sparkle/bin/generate_keys --account skitcho -x "$tmp/sparkle_private_key"
    gh secret set SPARKLE_ED_PRIVATE_KEY --env release --repo oleggohman/skitcho < "$tmp/sparkle_private_key"
    rm -rf "$tmp"
  )
  ```

  Do not use `-x /dev/stdout`: `generate_keys` writes an error string there instead of the key.
  Never export into the working tree (`.gitignore` covers `sparkle_private_key*`, but do not rely on it).

Keep a backup of the private key outside the repository, with owner-only permissions.
If it is lost, installed apps cannot be updated automatically.

`scripts/release.sh` derives the public key from `SPARKLE_ED_PRIVATE_KEY` (with Homebrew `openssl@3`)
and refuses to build when it does not match `SPARKLE_PUBLIC_ED_KEY`, or when the variable is empty or
not a 44-character base64 key. A mismatch would make every later update fail its signature check.

### 2. Apple signing and notarization secrets

Add these secrets to the `release` **environment** (names match the local `apple-signer` environment
variables):

| Secret | Content |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application certificate with private key, exported as `.p12`, base64-encoded (`base64 -i cert.p12`) |
| `DEVELOPER_ID_P12_PASSWORD` | Password of that `.p12` |
| `AppleIDENTITY` | Signing identity name, e.g. `Developer ID Application: Your Name (TEAMID)` |
| `AppleStoreAPIKey` | App Store Connect API key ID |
| `AppleIssuerID` | App Store Connect issuer ID |
| `ApplePrivateKey` | Contents of the App Store Connect `AuthKey_XXXX.p8` file |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle private key from step 1 |

Secrets are only passed through `env:` and are never printed by the workflow. `scripts/release.sh`
un-exports them, so the build tools never see them: the Sparkle key reaches `generate_appcast` on
stdin and the notarization values reach `notarytool` as arguments. A non-dry-run release refuses to
start without `AppleIDENTITY` (it never falls back to ad-hoc signing).

### 3. Protected `release` environment and tag rules

These settings are required, not optional:

- Environment `release` (Settings, Environments) with you as a **required reviewer**.
- Deployment branches and tags of that environment limited to the tag pattern `v*`.
- **All secrets are environment secrets** of `release`. Do not create repository-level secrets:
  any workflow on any pushed branch can read those without an approval.
- A tag ruleset that lets only admins create, update or delete `v*` tags.
- A `main` ruleset that requires a pull request.

The release job references this environment, so every release waits for an explicit approval
before any secret is exposed. The "tagged commit is on main" check lives in the workflow file of
the tagged commit, so it is only as trustworthy as that commit: the approver must review it.

### 4. Runner image

The workflows use the `macos-26` arm64 runner label. They select the highest release
`Xcode_27*.app` (betas and release candidates are skipped) and stop with an explicit
"expected Swift 6.4" or "expected an arm64 runner" error when the image does not match.
Update the label, the Xcode selection and the Swift version check together in `ci.yml`, `release.yml`
and the Swift job of `codeql.yml` if GitHub uses a different one.

## Releasing

1. Merge everything for the release to `main`. The workflow refuses tags whose commit is
   not an ancestor of `origin/main`.
2. Create and push a tag with the version, `vX.Y.Z`:

   ```bash
   git checkout main && git pull
   git tag v1.2.3
   git push origin v1.2.3
   ```

3. Before approving the pending deployment to the `release` environment, open the tagged commit
   in the run summary and confirm it is the reviewed `main` commit you meant to release, and that
   `.github/workflows/release.yml` and `scripts/` in that commit are unchanged from `main`. Then approve.
4. The workflow runs the tests, then `scripts/release.sh`:
   - Preflight, before anything is built or sent to Apple: the Sparkle key pair matches, the
     notarization values are set, `SIGN_IDENTITY` is a valid code signing identity in the keychain
     search list (an expired certificate fails here), and the published appcast is fetched. HTTP 200
     merges the feed; a 404 stops the release unless `FIRST_RELEASE=1` is set (see below); any other
     answer stops it too. The build number and `X.Y.Z` must both be greater than every published item.
     The notarization credentials themselves are only checked by `notarytool`, after the build.
   - Builds and signs the app inside-out with the hardened runtime and runs its `--self-test`.
   - Builds `Skitcho-X.Y.Z.dmg` (UDZO, volume `Skitcho`), signs the DMG, notarizes it
     (45 minute limit; the notary log is printed on failure), staples and validates the ticket
     and checks it with `spctl`.
   - Signs the DMG into `appcast.xml`, merged with the previous feed.
5. The workflow creates the GitHub release with `Skitcho-X.Y.Z.dmg` and `appcast.xml`, marked as
   latest. Installed apps read the feed from
   `https://github.com/oleggohman/skitcho/releases/latest/download/appcast.xml`.

Releases run one at a time (a `concurrency` group), and the job times out after 90 minutes.

### The first release

GitHub answers 404 for `releases/latest/download/appcast.xml` both when no release exists and when the
latest release has no `appcast.xml` asset (a manual release, a deleted asset). Treating the second case as
"no feed" would drop every older item and skip the version guards, so `scripts/release.sh` only accepts a
404 with an explicit `FIRST_RELEASE=1`, and refuses `FIRST_RELEASE=1` when a feed is published. The
workflow never sets it, so a tag run cannot publish the first release. `v0.1.0` is built locally on the
maintainer's Mac and published with `gh`:

1. Merge the release to `main`, then create and push the tag (only admins may, see the tag ruleset):

   ```bash
   git checkout main && git pull
   git tag v0.1.0
   git push origin v0.1.0
   ```

   The push starts the release workflow, which waits for approval of the `release` environment.
   **Reject** that deployment: without a feed it would stop at the 404 anyway.
2. Build from the tagged commit with a full clone (the build number is the commit count):

   ```bash
   git checkout --detach v0.1.0
   git status --porcelain   # must print nothing
   ```

   Set the same inputs the workflow gives `scripts/release.sh`, from your local `apple-signer`
   environment and the Sparkle key in your Keychain (step 1 of the setup):

   | Variable | Content |
   | --- | --- |
   | `SIGN_IDENTITY` | the `AppleIDENTITY` value; the certificate must be in your keychain search list |
   | `ASC_KEY_PATH` | path of the App Store Connect `AuthKey_XXXX.p8` file (outside the repository) |
   | `AppleStoreAPIKey`, `AppleIssuerID` | App Store Connect key ID and issuer ID |
   | `SPARKLE_PUBLIC_ED_KEY` | the repository variable of the same name |
   | `SPARKLE_ED_PRIVATE_KEY` | the private key, read from a private temporary export as in setup step 1 |

   Then run the release once with `FIRST_RELEASE=1`. It builds, signs, notarizes and staples the DMG
   and writes `dist/Skitcho-0.1.0.dmg` and a new `dist/appcast.xml`; it does not publish anything:

   ```bash
   FIRST_RELEASE=1 scripts/release.sh 0.1.0
   ```

3. Publish the release with both assets, marked as latest:

   ```bash
   gh release create v0.1.0 dist/Skitcho-0.1.0.dmg dist/appcast.xml \
     --repo oleggohman/skitcho --verify-tag --latest --title "Skitcho 0.1.0" --generate-notes
   ```

4. Check that the feed is published (expected output: `200`):

   ```bash
   curl -sSL -o /dev/null -w '%{http_code}\n' \
     https://github.com/oleggohman/skitcho/releases/latest/download/appcast.xml
   ```

5. Return to `main` (`git checkout main`) and unset the variables.

Every later release uses the tag workflow (see [Releasing](#releasing)), which requires this feed to exist.
Never set `FIRST_RELEASE` again. If a later release fails with "returned 404", restore `appcast.xml` on
the latest release instead.

## Verifying a release

Download the DMG from the release page and check Gatekeeper:

```bash
spctl -a -t open --context context:primary-signature -vv Skitcho-X.Y.Z.dmg
# expected: accepted, source=Notarized Developer ID
xcrun stapler validate Skitcho-X.Y.Z.dmg
hdiutil attach -nobrowse -readonly Skitcho-X.Y.Z.dmg
codesign --verify --deep --strict --verbose=2 /Volumes/Skitcho/Skitcho.app
hdiutil detach /Volumes/Skitcho
```

Then launch an older build and use Skitcho, Check for Updates to confirm the update is offered.

## Local dry run

`scripts/test-bundle.sh --release-dry-run` exercises `scripts/release.sh --dry-run` with a throwaway
key, a fixture appcast instead of the published feed, ad-hoc signing and no notarization. It checks
that the preflight rejects a bad key pair, stale versions, a misused `FIRST_RELEASE` and a CI release
from a non-tag ref, mounts the DMG read-only and asserts its contents, and verifies the appcast signature.
It never touches your Keychain. CI runs it on every push and pull request; the tag check applies only to
real releases, so the dry-run passes on branches.
