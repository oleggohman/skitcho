#!/usr/bin/env bash
# Lint the GitHub workflows: actionlint if installed, else a YAML parse; plus grep safety checks over the
# workflows and scripts/*.sh (no xtrace, no printed secrets, no zip packaging, SHA-pinned actions).
# Usage: scripts/test-workflows.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "error: $*" >&2
  exit 1
}

shopt -s nullglob
files=(.github/workflows/*.yml .github/workflows/*.yaml)
[[ ${#files[@]} -gt 0 ]] || fail "no workflow files found"

if command -v actionlint >/dev/null 2>&1; then
  actionlint "${files[@]}"
  echo "ok: actionlint"
elif python3 -I -c 'import yaml' 2>/dev/null; then
  python3 -I -c 'import sys, yaml
for f in sys.argv[1:]:
    yaml.safe_load(open(f))' "${files[@]}"
  echo "ok: yaml parse (python3)"
elif command -v ruby >/dev/null 2>&1; then
  ruby -ryaml -e 'ARGV.each { |f| YAML.safe_load(File.read(f)) }' "${files[@]}"
  echo "ok: yaml parse (ruby)"
else
  fail "neither actionlint, python3 yaml nor ruby is available"
fi

# Secret-hygiene checks cover the workflows and every shell script they run. Comment lines are ignored.
code_lines() { grep -nE "$1" "$2" | grep -vE '^[0-9]+:[[:space:]]*#' || true; }
xtrace_re='(^|[^A-Za-z_])set[[:space:]]+-[A-Za-z]*x|-o[[:space:]]+xtrace|(^|[^A-Za-z_])(ba|z)?sh[[:space:]]+-[A-Za-z]*x'
secret_re='secrets\.|DEVELOPER_ID_P12|APPLE_PRIVATE_KEY|AppleStoreAPIKey|AppleIssuerID|SPARKLE_ED_PRIVATE_KEY|KC_PW'
for f in "${files[@]}" scripts/*.sh; do
  hits="$(code_lines "$xtrace_re" "$f")"
  [[ -z "$hits" ]] || fail "$f enables xtrace: $hits"
  # echo/printf of a secret is only allowed into a pipe or a file; writing non-secret paths to
  # $GITHUB_ENV is fine. Anything else (stdout, stderr) would land in the log.
  hits="$(code_lines '(^|[^A-Za-z_])(echo|printf)([^A-Za-z_]|$)' "$f" |
    grep -vE 'GITHUB_ENV|ASC_KEY_PATH=|SIGN_IDENTITY=' | grep -E "$secret_re" |
    grep -vE '[^|][|][^|]|>>?[[:space:]]*"\$[A-Za-z0-9_]+"' || true)"
  [[ -z "$hits" ]] || fail "$f prints a secret: $hits"
done

# Releases ship a DMG; the zip packaging is gone for good.
hits="$(grep -nE 'ditto[[:space:]]+-c[[:space:]]+-k|[.]zip([^A-Za-z]|$)' "${files[@]}" scripts/*.sh || true)"
[[ -z "$hits" ]] || fail "zip packaging left over: $hits"
grep -qE 'gh release create .*dist/Skitcho-\*[.]dmg dist/appcast[.]xml' .github/workflows/release.yml ||
  fail "release.yml does not upload dist/Skitcho-*.dmg and dist/appcast.xml"

for f in "${files[@]}"; do
  # Every action reference must be pinned to a 40-hex commit SHA.
  while IFS= read -r line; do
    ref="${line#*uses:}"
    ref="${ref// /}"
    ref="${ref%%#*}"
    [[ "$ref" =~ @[0-9a-f]{40}$ ]] || fail "$f: action not SHA-pinned: $line"
    # Only GitHub-owned actions, plus the OpenSSF Scorecard action.
    [[ "$ref" =~ ^(actions|github)/ || "$ref" =~ ^ossf/scorecard-action@ ]] ||
      fail "$f: action owner not allowed (GitHub-owned or ossf/scorecard-action only): $line"
  done < <(grep -E '^[[:space:]]*(- )?uses:' "$f")
done
echo "ok: workflow and script grep checks (${#files[@]} workflows, scripts/*.sh)"

# Security workflows: they must exist, start from empty token permissions and never persist credentials.
for w in codeql dependency-review scorecard trivy; do
  [[ -f ".github/workflows/$w.yml" ]] || fail "missing .github/workflows/$w.yml"
done
for w in codeql scorecard trivy; do
  grep -qE '^permissions:[[:space:]]*\{\}[[:space:]]*$' ".github/workflows/$w.yml" ||
    fail "$w.yml must set top-level 'permissions: {}'"
done
for f in "${files[@]}"; do
  # Every checkout must opt out of persisting the token.
  n_checkout="$(grep -cE 'uses:[[:space:]]*actions/checkout@' "$f" || true)"
  n_persist="$(grep -cE '^[[:space:]]*persist-credentials:[[:space:]]*false' "$f" || true)"
  [[ "$n_checkout" -le "$n_persist" ]] || fail "$f: actions/checkout without persist-credentials: false"
  # Pins must carry a trailing version comment.
  hits="$(grep -E '^[[:space:]]*(- )?uses:' "$f" | grep -vE '@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v[0-9]+[.][0-9]+[.][0-9]+' || true)"
  [[ -z "$hits" ]] || fail "$f: action pin without '# vX.Y.Z' comment: $hits"
  # No secrets in these workflows beyond what the repo's other workflows already use.
  case "$f" in
    *codeql.yml | *dependency-review.yml | *scorecard.yml | *trivy.yml)
      hits="$(code_lines 'secrets\.' "$f")"
      [[ -z "$hits" ]] || fail "$f references secrets: $hits"
      ;;
  esac
done
# The Trivy binary is pinned by a hardcoded checksum (trivy-action is not allowed by policy).
grep -qE '^[[:space:]]*TRIVY_SHA256:[[:space:]]*[0-9a-f]{64}[[:space:]]*$' .github/workflows/trivy.yml ||
  fail "trivy.yml: TRIVY_SHA256 must be a hardcoded 64-hex checksum"
grep -q 'sha256sum -c' .github/workflows/trivy.yml || fail "trivy.yml does not verify the download checksum"
! grep -qE 'uses:[[:space:]]*aquasecurity/' .github/workflows/trivy.yml || fail "trivy.yml must not use trivy-action"
for y in .github/dependabot.yml .github/ISSUE_TEMPLATE/*.yml; do
  ruby -ryaml -e 'YAML.safe_load(File.read(ARGV[0]))' "$y" || fail "$y does not parse"
done
echo "ok: security workflow checks, dependabot and issue form YAML"
