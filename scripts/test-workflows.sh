#!/usr/bin/env bash
# Lint the GitHub workflows: actionlint if installed, else a YAML parse; plus grep safety checks.
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
elif python3 -c 'import yaml' 2>/dev/null; then
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

for f in "${files[@]}"; do
  if grep -nE '(^|[^A-Za-z_])set[[:space:]]+-[A-Za-z]*x' "$f"; then
    fail "$f uses set -x"
  fi
  # Writing to $GITHUB_ENV is fine (non-secret paths); any other echo of a secret variable is not.
  if grep -E '\<echo\>' "$f" | grep -vE 'GITHUB_ENV|ASC_KEY_PATH=|SIGN_IDENTITY=' |
    grep -E 'secrets\.|DEVELOPER_ID_P12|APPLE_PRIVATE_KEY|AppleStoreAPIKey|SPARKLE_ED_PRIVATE_KEY|KC_PW'; then
    fail "$f echoes a secret"
  fi
  # Every action reference must be pinned to a 40-hex commit SHA.
  while IFS= read -r line; do
    ref="${line#*uses:}"
    ref="${ref// /}"
    ref="${ref%%#*}"
    [[ "$ref" =~ @[0-9a-f]{40}$ ]] || fail "$f: action not SHA-pinned: $line"
  done < <(grep -E '^[[:space:]]*(- )?uses:' "$f")
done
echo "ok: workflow grep checks (${#files[@]} files)"
