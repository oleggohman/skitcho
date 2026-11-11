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
- Builds are arm64-only.

Details for maintainers are in [docs/RELEASING.md](docs/RELEASING.md).

## Secrets

No secret (private signing key, certificate, API key, password) is ever committed to this repository.
They live only in GitHub Actions secrets and the maintainer's keychain. If you find one in the history,
report it as described above.
