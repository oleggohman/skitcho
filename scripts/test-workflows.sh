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
  done < <(grep -E '^[[:space:]]*(- )?uses:' "$f")
done
echo "ok: workflow and script grep checks (${#files[@]} workflows, scripts/*.sh)"
