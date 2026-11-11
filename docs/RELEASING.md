# Releasing Skitcho

Releases are built, signed, notarized and published by `.github/workflows/release.yml`
when a `v*` tag is pushed. This page describes the one-time maintainer setup and the
per-release flow. No secret value ever belongs in the repository.

## One-time setup

### 1. Sparkle update signing key

Sparkle verifies updates with an EdDSA key pair. Create it once on a trusted Mac:

```bash
swift build --arch arm64   # fetches the Sparkle artifact bundle
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

`generate_keys` stores the private key in your login Keychain and prints the public key.

- Put the printed **public** key in the repository variable `SPARKLE_PUBLIC_ED_KEY`
  (Settings, Secrets and variables, Actions, Variables). It is embedded in the app as `SUPublicEDKey`.
- Export the **private** key to a file, copy its contents into the secret
  `SPARKLE_ED_PRIVATE_KEY`, then delete the file:

  ```bash
  .build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private_key
  # paste the file contents into the GitHub secret, then:
  rm sparkle_private_key
  ```

Keep a backup of the private key in a password manager. If it is lost, installed apps
cannot be updated automatically.

### 2. Apple signing and notarization secrets

Add these Actions secrets (names match the local `apple-signer` environment variables):

| Secret | Content |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application certificate with private key, exported as `.p12`, base64-encoded (`base64 -i cert.p12`) |
| `DEVELOPER_ID_P12_PASSWORD` | Password of that `.p12` |
| `AppleIDENTITY` | Signing identity name, e.g. `Developer ID Application: Your Name (TEAMID)` |
| `AppleStoreAPIKey` | App Store Connect API key ID |
| `AppleIssuerID` | App Store Connect issuer ID |
| `ApplePrivateKey` | Contents of the App Store Connect `AuthKey_XXXX.p8` file |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle private key from step 1 |

Secrets are only passed through `env:` and are never printed by the workflow.

### 3. Protected `release` environment

Create the environment `release` (Settings, Environments) and add yourself as a
**required reviewer**. The release job references this environment, so every release
waits for an explicit approval before any secret is exposed. Optionally restrict the
environment to deployment tags matching `v*`. Put the secrets above in the environment
(or at repository level) as you prefer.

### 4. Runner image

The workflows use the `macos-26` arm64 runner label as a placeholder. Confirm that the
image provides Xcode 27.x and Swift 6.4 (the workflow fails fast if it does not) and
update the label in `ci.yml` and `release.yml` if GitHub uses a different one.

## Releasing

1. Merge everything for the release to `main`. The workflow refuses tags whose commit is
   not an ancestor of `origin/main`.
2. Create and push a tag with the version, `vX.Y.Z`:

   ```bash
   git checkout main && git pull
   git tag v1.2.3
   git push origin v1.2.3
   ```

3. Approve the pending deployment to the `release` environment in the Actions run.
4. The workflow runs the tests, builds and signs the app, notarizes and staples it, zips
   it, merges `appcast.xml` with the previous feed, and creates the GitHub release with
   `Skitcho-X.Y.Z.zip` and `appcast.xml` attached. Installed apps read the feed from
   `https://github.com/oleggohman/skitcho/releases/latest/download/appcast.xml`.

The build number must be greater than the latest published `sparkle:version`;
`scripts/release.sh` fails otherwise.

## Verifying a release

Download the zip from the release page, unzip it and check Gatekeeper:

```bash
spctl -a -t exec -vv Skitcho.app
# expected: accepted, source=Notarized Developer ID
xcrun stapler validate Skitcho.app
codesign --verify --deep --strict --verbose=2 Skitcho.app
```

Then launch an older build and use Skitcho, Check for Updates to confirm the update is offered.

## Local dry run

`scripts/test-bundle.sh --release-dry-run` exercises the release script (bundle, zip,
appcast signing) with a throwaway key and without notarization. It never touches your Keychain.
