# Releasing Skitcho

Skitcho is built, signed, notarized and released only on the maintainer's Mac. There is no CI build and no
release automation: GitHub only runs the Linux security scans (CodeQL on the workflow files, Trivy,
dependency review, Scorecard). Every release, including the first, follows the local procedure below and
ends with a manual `gh release create`. Each release ships `Skitcho-X.Y.Z.dmg` (a compressed disk image
with `Skitcho.app` and an `Applications` link for drag-to-install), its minisign signature
`Skitcho-X.Y.Z.dmg.minisig` and `appcast.xml`. Signatures start with 0.1.2: v0.1.1 was published before
and has none, and its release is immutable, so none can be added. No secret value ever belongs in the
repository, and none belongs in GitHub.

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

4. **minisign release signing key.** Every release DMG also gets a minisign signature, so users can check a
   download against a key published in the repository, independently of GitHub and Apple. The secret key
   is password-protected and lives outside the repository at `~/.minisign/skitcho.key`; the public key is
   committed as `minisign.pub` (key id `81041D060E47AEF8`) and printed in [SECURITY.md](../SECURITY.md)
   and the README. Create the pair once, in the repository root (minisign asks for the password twice):

   ```bash
   brew install minisign
   mkdir -p ~/.minisign && chmod 700 ~/.minisign
   minisign -G -p minisign.pub -s ~/.minisign/skitcho.key
   ```

   This is done; do not run it again. Keep a backup of `~/.minisign/skitcho.key` and its password somewhere
   private, with owner-only permissions. If the key is lost, generate a new pair, commit the new
   `minisign.pub` and update the key string in SECURITY.md and README.md.

   For unattended signing, store the key password in the login Keychain (service `skitcho-minisign`,
   account `skitcho`). `security` prompts for the password, so it never appears on the command line:

   ```bash
   security add-generic-password -a skitcho -s skitcho-minisign -w
   ```

   Add `-U` to update the item after a password change. This is done. Because `security` created the item,
   reading it back usually shows no dialog; if macOS asks for Keychain access, choose Always Allow so later
   releases run unattended.

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
   | `MINISIGN_SECRET_KEY` | path of the minisign secret key, `~/.minisign/skitcho.key` |
   | `MINISIGN_PASSWORD` | optional: the minisign key password, read from the Keychain (setup step 4); empty counts as unset |

   `MINISIGN_PUBLIC_KEY_FILE` defaults to `minisign.pub` at the repository root; leave it unset for a real
   release (only the dry run overrides it). A real release stops in the preflight when it points anywhere
   else.

   Export the Sparkle private key into a `umask 077` temporary directory outside the repository, read the
   minisign password from the Keychain, run the release, and delete the export again. Set
   `MINISIGN_PASSWORD` last, right before `scripts/release.sh`, so the earlier commands do not inherit it;
   `|| exit 1` stops the subshell when the Keychain item is missing:

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
     export MINISIGN_SECRET_KEY="$HOME/.minisign/skitcho.key"
     MINISIGN_PASSWORD="$(security find-generic-password -a skitcho -s skitcho-minisign -w)" || exit 1
     export MINISIGN_PASSWORD
     scripts/release.sh X.Y.Z
   )
   ```

   Do not use `-x /dev/stdout`: `generate_keys` writes an error string there instead of the key. Never
   export into the working tree. Add `FIRST_RELEASE=1` to the `scripts/release.sh` call for `v0.1.1` only
   (see [The first release](#the-first-release)). Bug-fix releases bump the patch version by 0.0.1
   (0.1.1, then 0.1.2).

   With `MINISIGN_PASSWORD` set, `release.sh` pipes it to every `minisign -S` call from the `printf`
   builtin (never on argv, on disk or in the output), needs no terminal and never prompts. It un-exports
   the variable (`export -n`), so no other child process sees it.

   Only when `MINISIGN_PASSWORD` is unset does minisign read the key password from stdin. Then run
   `scripts/release.sh` from an interactive terminal, with no pipe or redirect into it (the preflight stops
   with "stdin is not a terminal: minisign needs it for the key password (or set MINISIGN_PASSWORD)"
   otherwise). It asks twice: once in the preflight, and again at the end, after notarization, which can
   take many minutes. Stay at the terminal.

   `scripts/release.sh` then:
   - Preflight, before anything is built or sent to Apple: the Sparkle key pair matches, the
     notarization values are set, `SIGN_IDENTITY` is a valid code signing identity in the keychain
     search list (an expired certificate fails here), minisign is installed, `MINISIGN_SECRET_KEY` points
     to a readable file, the public key file is the committed `minisign.pub`, stdin is a terminal (only
     when `MINISIGN_PASSWORD` is unset), and a test signature of a scratch file verifies with it (first
     password prompt without `MINISIGN_PASSWORD`; a wrong key or password stops here with
     "MINISIGN_SECRET_KEY does not match ... (or wrong password / MINISIGN_PASSWORD)"), and the published
     appcast is fetched. HTTP 200
     merges the feed; a 404 stops the release unless `FIRST_RELEASE=1` is set; any other answer stops it
     too. The build number and `X.Y.Z` must both be greater than every published item. The notarization
     credentials themselves are only checked by `notarytool`, after the build.
   - Builds and signs the app inside-out with the hardened runtime and runs its `--self-test`.
   - Builds `Skitcho-X.Y.Z.dmg` (UDZO, volume `Skitcho`), signs the DMG, notarizes it
     (45 minute limit; the notary log is printed on failure), staples and validates the ticket
     and checks it with `spctl`.
   - Signs the DMG into `appcast.xml`, merged with the previous feed.
   - Signs the final DMG with minisign into `Skitcho-X.Y.Z.dmg.minisig`, trusted comment
     `Skitcho X.Y.Z Skitcho-X.Y.Z.dmg`, and verifies it with the public key (one attempt with
     `MINISIGN_PASSWORD`; without it, the second password prompt, up to 3 attempts on a terminal).
   - Writes `dist/Skitcho-X.Y.Z.dmg`, `dist/Skitcho-X.Y.Z.dmg.minisig` and `dist/appcast.xml`. It un-exports the secrets, so the build tools
     never see them: the Sparkle key reaches `generate_appcast` on stdin and the notarization values reach
     `notarytool` as arguments. A non-dry-run release refuses to start without `SIGN_IDENTITY` (it never
     falls back to ad-hoc signing).

   If the final minisign signature fails, `release.sh` stops with an error, but `dist/` already holds the
   final, notarized DMG and `appcast.xml`. Never re-run `release.sh` for the same version: it would rebuild
   and re-notarize a different DMG. Sign by hand with the commands it prints, then continue with step 4:

   ```bash
   minisign -S -s ~/.minisign/skitcho.key -m dist/Skitcho-X.Y.Z.dmg -x dist/Skitcho-X.Y.Z.dmg.minisig \
     -t "Skitcho X.Y.Z Skitcho-X.Y.Z.dmg"
   minisign -V -p minisign.pub -m dist/Skitcho-X.Y.Z.dmg -x dist/Skitcho-X.Y.Z.dmg.minisig
   ```

4. Only after step 3 succeeded, tag the same commit and push the tag (only admins may, see the tag
   ruleset):

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

5. Publish the release with all three assets, marked as latest:

   ```bash
   gh release create vX.Y.Z dist/Skitcho-X.Y.Z.dmg dist/Skitcho-X.Y.Z.dmg.minisig dist/appcast.xml \
     --repo oleggohman/skitcho --verify-tag --latest --title "Skitcho X.Y.Z" --generate-notes
   ```

   Pass every asset in this one command: releases are immutable, so no asset can be added after the
   release is published.

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
gh release create v0.1.1 dist/Skitcho-0.1.1.dmg dist/Skitcho-0.1.1.dmg.minisig dist/appcast.xml \
  --repo oleggohman/skitcho --verify-tag --latest --title "Skitcho 0.1.1" --generate-notes
```

The published v0.1.1 predates minisign signing and has no `.minisig`; the block shows the commands as the
current `release.sh` runs them.

## Verifying a release

Download the DMG and its `.minisig` from the release page into the same directory and check the minisign
signature (0.1.2 and later; minisign 0.8 or later):

```bash
minisign -Vm Skitcho-X.Y.Z.dmg -P RWT4rkcOBh0Egd4d1Nc/WaPdz5wNdMeFOQ5hV/PdEo0qSVAblgc5qBim
# expected: Signature and comment signature verified
#           Trusted comment: Skitcho X.Y.Z Skitcho-X.Y.Z.dmg
```

Then check Gatekeeper:

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
Sparkle key, throwaway unencrypted minisign key pairs plus a throwaway password-encrypted pair with a
test-only password, a fixture appcast instead of the published feed, ad-hoc signing and no notarization. It
needs minisign (`brew install minisign`). It checks that the preflight rejects a bad Sparkle key pair,
stale versions, a misused `FIRST_RELEASE`, an unset `MINISIGN_SECRET_KEY`, a missing minisign key file, a
minisign key that does not match the public key and the encrypted key with a wrong `MINISIGN_PASSWORD`.
The full run takes the unattended path (the encrypted key with the correct `MINISIGN_PASSWORD`, stdin from
`/dev/null`), mounts the DMG read-only and asserts its contents, and verifies the appcast signature. It
verifies `dist/Skitcho-9.9.9.dmg.minisig` with the throwaway public key, checks its trusted comment, and
checks that another public key rejects it. It asserts that neither test password appears in the release
log. It never touches your Keychain, `~/.minisign` or the committed
`minisign.pub` (it asserts the file is unchanged), and never waits for a password.
