# Security

## Reporting a vulnerability

Please report vulnerabilities privately. Do not open a public issue.

Use GitHub private vulnerability reporting: open the repository's Security tab and choose
"Report a vulnerability" (or go to
[github.com/oleggohman/skitcho/security/advisories/new](https://github.com/oleggohman/skitcho/security/advisories/new)).
Describe the problem, the affected version and steps to reproduce. Only the latest release is supported.

## Update signing model

- Updates are delivered by Sparkle 2. The appcast is signed with an EdDSA key; the app embeds the
  matching public key (`SUPublicEDKey`) and refuses updates that do not verify.
- Release builds are signed with a Developer ID Application certificate and are notarized and stapled by
  Apple before publication.
- From 0.1.2 on, every release DMG also carries a minisign signature, published as the release asset
  `Skitcho-X.Y.Z.dmg.minisig`. The public key (key id `81041D060E47AEF8`, also committed as
  [`minisign.pub`](minisign.pub)) is:

  ```
  RWT4rkcOBh0Egd4d1Nc/WaPdz5wNdMeFOQ5hV/PdEo0qSVAblgc5qBim
  ```

  Download the DMG and its `.minisig` into the same directory and verify with minisign 0.8 or later
  (`brew install minisign`):

  ```bash
  minisign -Vm Skitcho-X.Y.Z.dmg -P RWT4rkcOBh0Egd4d1Nc/WaPdz5wNdMeFOQ5hV/PdEo0qSVAblgc5qBim
  ```

  v0.1.1 has no signature: it was published before signing started, and its release is immutable.
- Builds are arm64-only.

Details for maintainers are in [docs/RELEASING.md](docs/RELEASING.md).

## Secrets

No secret (private signing key, certificate, API key, password) is ever committed to this repository.
They live only in the maintainer's keychain and are never stored in GitHub. If you find one in the history,
report it as described above.
