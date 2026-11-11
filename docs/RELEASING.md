# Releasing Skitcho

Skitcho is built, signed, notarized and released only on the maintainer's Mac. There is no CI build and no
release automation: GitHub only runs the Linux security scans (CodeQL on the workflow files, Trivy,
dependency review, Scorecard). Every release, including the first, follows the local procedure below and
ends with a manual `gh release create`. Each release ships `Skitcho-X.Y.Z.dmg` (a compressed disk image
with `Skitcho.app` and an `Applications` link for drag-to-install) and `appcast.xml`. No secret value ever
belongs in the repository, and none belongs in GitHub.

The former `release` GitHub environment and its secrets are no longer used by anything. They can be
deleted from the repository settings.

## One-time setup

1. **Developer ID certificate.** The Developer ID Application certificate with its private key is in your
   login keychain, and `security find-identity -v -p codesigning` lists it (an expired certificate does not
   count). Its name, e.g. `Developer ID Application: Your Name (TEAMID)`, is the `SIGN_IDENTITY` value.
2. **App Store Connect key.** An App Store Connect API key for notarization: the `AuthKey_XXXX.p8` file
   (kept outside the repository), its key ID (`AppleStoreAPIKey`) and the issuer ID (`AppleIssuerID`).
3. **Sparkle update signing key.** Sparkle verifies updates with an EdDSA key pair. The private key lives in
   the login Keychain under the account `skitcho`. Create it once:

   ```bash
   swift build --arch arm64   # fetches the Sparkle artifact bundle
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account skitcho
   ```

   `generate_keys` stores the private key in your login Keychain and prints the **public** key, which is
   `SPARKLE_PUBLIC_ED_KEY` (it is embedded in the app as `SUPublicEDKey`). Running it again with the same
   `--account` only prints the existing public key. Keep a backup of the private key somewhere private,
   with owner-only permissions. If it is lost, installed apps cannot be updated automatically.

`scripts/release.sh` derives the public key from `SPARKLE_ED_PRIVATE_KEY` (with Homebrew `openssl@3`)
and refuses to build when it does not match `SPARKLE_PUBLIC_ED_KEY`, or when the variable is empty or
not a 44-character base64 key. A mismatch would make every later update fail its signature check.

Repository rules (Settings, Rules): a tag ruleset that lets only admins create, update or delete `v*` tags,
and a `main` ruleset that requires a pull request.

## Releasing

Build first and tag only after the build succeeded: the tag ruleset blocks moving or deleting a pushed
`v*` tag, so a tag pushed before a failed build would strand the version. The build number is the commit
count, so use a full clone and build exactly the commit that gets tagged.

1. Merge everything for the release to `main`.
2. Detach at main's commit and check that the tree is clean:

   ```bash
   git checkout main && git pull
   git checkout --detach "$(git rev-parse main)"
   git status --porcelain   # must print nothing
   ```

3. Set the environment and run the release. Nothing is published by this step.

   | Variable | Content |
   | --- | --- |
   | `SIGN_IDENTITY` | the Developer ID Application identity name from setup step 1 |
   | `ASC_KEY_PATH` | path of the App Store Connect `AuthKey_XXXX.p8` file (outside the repository) |
   | `AppleStoreAPIKey`, `AppleIssuerID` | App Store Connect key ID and issuer ID |
   | `SPARKLE_PUBLIC_ED_KEY` | the public key printed by `generate_keys` |
   | `SPARKLE_ED_PRIVATE_KEY` | the private key, read from a private temporary export |

   Export the Sparkle private key into a `umask 077` temporary directory outside the repository, run the
   release, and delete the export again:

   ```bash
   (
     umask 077
     tmp="$(mktemp -d)"
     trap 'rm -rf "$tmp"' EXIT
     .build/artifacts/sparkle/Sparkle/bin/generate_keys --account skitcho -x "$tmp/sparkle_private_key"
     export SPARKLE_ED_PRIVATE_KEY="$(cat "$tmp/sparkle_private_key")"
     export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
     export ASC_KEY_PATH="/path/to/AuthKey_XXXX.p8"
     export AppleStoreAPIKey="..." AppleIssuerID="..." SPARKLE_PUBLIC_ED_KEY="..."
     scripts/release.sh X.Y.Z
   )
   ```

   Do not use `-x /dev/stdout`: `generate_keys` writes an error string there instead of the key. Never
   export into the working tree. Add `FIRST_RELEASE=1` to the `scripts/release.sh` call for `v0.1.1` only
   (see [The first release](#the-first-release)). Bug-fix releases bump the patch version by 0.0.1
   (0.1.1, then 0.1.2).

   `scripts/release.sh` then:
   - Preflight, before anything is built or sent to Apple: the Sparkle key pair matches, the
     notarization values are set, `SIGN_IDENTITY` is a valid code signing identity in the keychain
     search list (an expired certificate fails here), and the published appcast is fetched. HTTP 200
     merges the feed; a 404 stops the release unless `FIRST_RELEASE=1` is set; any other answer stops it
     too. The build number and `X.Y.Z` must both be greater than every published item. The notarization
     credentials themselves are only checked by `notarytool`, after the build.
   - Builds and signs the app inside-out with the hardened runtime and runs its `--self-test`.
   - Builds `Skitcho-X.Y.Z.dmg` (UDZO, volume `Skitcho`), signs the DMG, notarizes it
     (45 minute limit; the notary log is printed on failure), staples and validates the ticket
     and checks it with `spctl`.
   - Signs the DMG into `appcast.xml`, merged with the previous feed.
   - Writes `dist/Skitcho-X.Y.Z.dmg` and `dist/appcast.xml`. It un-exports the secrets, so the build tools
     never see them: the Sparkle key reaches `generate_appcast` on stdin and the notarization values reach
     `notarytool` as arguments. A non-dry-run release refuses to start without `SIGN_IDENTITY` (it never
     falls back to ad-hoc signing).

4. Only after step 3 succeeded, tag the same commit and push the tag (only admins may, see the tag
   ruleset):

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

5. Publish the release with both assets, marked as latest:

   ```bash
   gh release create vX.Y.Z dist/Skitcho-X.Y.Z.dmg dist/appcast.xml \
     --repo oleggohman/skitcho --verify-tag --latest --title "Skitcho X.Y.Z" --generate-notes
   ```

   Installed apps read the feed from
   `https://github.com/oleggohman/skitcho/releases/latest/download/appcast.xml`.

6. Check that the feed is published (expected output: `200`):

   ```bash
   curl -sSL -o /dev/null -w '%{http_code}\n' \
     https://github.com/oleggohman/skitcho/releases/latest/download/appcast.xml
   ```

7. Verify Gatekeeper on the downloaded DMG (see [Verifying a release](#verifying-a-release)).
8. Return to `main` (`git checkout main`) and unset the variables.

### The first release

GitHub answers 404 for `releases/latest/download/appcast.xml` both when no release exists and when the
latest release has no `appcast.xml` asset (a manual release, a deleted asset). Treating the second case as
"no feed" would drop every older item and skip the version guards, so `scripts/release.sh` only accepts a
404 with an explicit `FIRST_RELEASE=1`, and refuses `FIRST_RELEASE=1` when a feed is published. Set it for
`v0.1.1`, the first public release, only and never again. If a later release fails with "returned 404",
restore `appcast.xml` on the latest release instead.

For the first release, steps 3 to 5 read:

```bash
FIRST_RELEASE=1 scripts/release.sh 0.1.1   # inside the subshell of step 3; writes dist/Skitcho-0.1.1.dmg
git tag v0.1.1
git push origin v0.1.1
gh release create v0.1.1 dist/Skitcho-0.1.1.dmg dist/appcast.xml \
  --repo oleggohman/skitcho --verify-tag --latest --title "Skitcho 0.1.1" --generate-notes
```

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
that the preflight rejects a bad key pair, stale versions and a misused `FIRST_RELEASE`, mounts the DMG
read-only and asserts its contents, and verifies the appcast signature. It never touches your Keychain.
