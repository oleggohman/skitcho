#!/usr/bin/env bash
# Build, sign, (notarize), zip and prepare a release: dist/Skitcho-VERSION.zip + dist/appcast.xml.
# Usage: scripts/release.sh VERSION [--dry-run]
# Env: SIGN_IDENTITY, SPARKLE_PUBLIC_ED_KEY (read by bundle.sh), SPARKLE_ED_PRIVATE_KEY (appcast signing),
#      ASC_KEY_PATH, AppleStoreAPIKey, AppleIssuerID (notarization, skipped with --dry-run).
# Secrets are only read from the environment and never printed. Do not add `set -x`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || fail "usage: release.sh VERSION [--dry-run]"
VERSION="$1"
DRY_RUN=0
if [[ $# -eq 2 ]]; then
  [[ "$2" == "--dry-run" ]] || fail "unknown option '$2'"
  DRY_RUN=1
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION must match X.Y.Z (got '$VERSION')"
if [[ "${GITHUB_ACTIONS:-}" == "true" && "${GITHUB_REF_NAME:-}" != "v$VERSION" ]]; then
  fail "GITHUB_REF_NAME '${GITHUB_REF_NAME:-}' does not match v$VERSION"
fi
[[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]] || fail "SPARKLE_ED_PRIVATE_KEY is not set"

APP="$ROOT/build/Skitcho.app"
DIST="$ROOT/dist"
ZIP="$DIST/Skitcho-$VERSION.zip"
GA="$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
PREFIX="https://github.com/oleggohman/skitcho/releases/download/v$VERSION/"

# bundle.sh reads VERSION, SIGN_IDENTITY and SPARKLE_PUBLIC_ED_KEY from the environment.
VERSION="$VERSION" "$ROOT/scripts/bundle.sh"

BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"

rm -rf "$DIST"
mkdir -p "$DIST"
make_zip() {
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
}
make_zip

if [[ "$DRY_RUN" == 0 ]]; then
  : "${ASC_KEY_PATH:?ASC_KEY_PATH is not set}" "${AppleStoreAPIKey:?AppleStoreAPIKey is not set}" \
    "${AppleIssuerID:?AppleIssuerID is not set}"
  result="$(xcrun notarytool submit "$ZIP" --key "$ASC_KEY_PATH" --key-id "$AppleStoreAPIKey" \
    --issuer "$AppleIssuerID" --wait --output-format json)"
  status="$(printf '%s' "$result" | plutil -extract status raw -o - -)"
  if [[ "$status" != "Accepted" ]]; then
    sub_id="$(printf '%s' "$result" | plutil -extract id raw -o - -)"
    xcrun notarytool log "$sub_id" --key "$ASC_KEY_PATH" --key-id "$AppleStoreAPIKey" \
      --issuer "$AppleIssuerID" || true
    fail "notarization status '$status'"
  fi
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  make_zip
  spctl_out="$(spctl -a -t exec -vv "$APP" 2>&1 || true)"
  echo "$spctl_out"
  grep -q 'Notarized Developer ID' <<<"$spctl_out" || fail "spctl does not report Notarized Developer ID"
else
  echo "dry-run: skipping notarization"
fi

# The previous appcast keeps older versions in the feed; a 404 on the first release is fine.
curl -fsSL https://github.com/oleggohman/skitcho/releases/latest/download/appcast.xml -o "$DIST/appcast.xml" ||
  rm -f "$DIST/appcast.xml"
if [[ -f "$DIST/appcast.xml" ]]; then
  max="$(grep -oE 'sparkle:version(>|=")[0-9]+' "$DIST/appcast.xml" | grep -oE '[0-9]+$' | sort -n | tail -1 || true)"
  if [[ -n "$max" && "$BUILD_NUMBER" -le "$max" ]]; then
    fail "build number $BUILD_NUMBER is not greater than published sparkle:version $max"
  fi
fi

[[ -x "$GA" ]] || fail "generate_appcast not found at $GA (run swift build first)"
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$GA" --ed-key-file - --maximum-versions 0 \
  --download-url-prefix "$PREFIX" "$DIST"

echo "release ok: $ZIP (version $VERSION build $BUILD_NUMBER, dry-run=$DRY_RUN)"
