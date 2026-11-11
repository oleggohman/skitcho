#!/usr/bin/env bash
# Build the bundle and assert its structure, architecture, signature and repo hygiene.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if [[ "${1:-}" == "--release-dry-run" ]]; then
  # Throwaway ed25519 key that never touches the Keychain or Sparkle's generate_keys.
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  OPENSSL="$(brew --prefix openssl@3 2>/dev/null || true)/bin/openssl"
  [[ -x "$OPENSSL" ]] || OPENSSL=openssl # /usr/bin/openssl is LibreSSL and may lack ed25519
  "$OPENSSL" genpkey -algorithm ed25519 -out "$WORK/key.pem" 2>/dev/null ||
    fail "$OPENSSL cannot generate ed25519 keys (install openssl@3: brew install openssl@3)"
  "$OPENSSL" pkey -in "$WORK/key.pem" -outform DER | tail -c 32 | base64 >"$WORK/seed"
  PUB="$("$OPENSSL" pkey -in "$WORK/key.pem" -pubout -outform DER | tail -c 32 | base64)"

  DRY_VERSION="9.9.9"
  rm -rf "$ROOT/dist"
  SPARKLE_ED_PRIVATE_KEY="$(cat "$WORK/seed")" SPARKLE_PUBLIC_ED_KEY="$PUB" SIGN_IDENTITY="" \
    "$ROOT/scripts/release.sh" "$DRY_VERSION" --dry-run || fail "release.sh --dry-run failed"

  ZIP="$ROOT/dist/Skitcho-$DRY_VERSION.zip"
  APPCAST="$ROOT/dist/appcast.xml"
  [[ -f "$ZIP" ]] || fail "missing $ZIP"
  [[ -f "$APPCAST" ]] || fail "missing appcast.xml"

  # The zip holds an arm64-only app.
  UNZIP="$WORK/unzip"
  mkdir -p "$UNZIP"
  ditto -x -k "$ZIP" "$UNZIP"
  zmacho=0
  while IFS= read -r -d '' f; do
    if file -b "$f" | grep -q 'Mach-O'; then
      [[ "$(lipo -archs "$f")" == "arm64" ]] || fail "zip: $f is not thin arm64"
      zmacho=$((zmacho + 1))
    fi
  done < <(find "$UNZIP/Skitcho.app" -type f -print0)
  [[ "$zmacho" -ge 1 ]] || fail "zip: no Mach-O found"
  codesign --verify --deep --strict "$UNZIP/Skitcho.app" || fail "zip: codesign verification failed"
  zpub="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$UNZIP/Skitcho.app/Contents/Info.plist")"
  [[ "$zpub" == "$PUB" ]] || fail "zip: SUPublicEDKey does not match the dry-run key"

  # appcast.xml parses, carries an edSignature and the right enclosure URL.
  xmllint --noout "$APPCAST" || fail "appcast.xml does not parse"
  want_url="https://github.com/oleggohman/skitcho/releases/download/v$DRY_VERSION/Skitcho-$DRY_VERSION.zip"
  got_url="$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@url)' "$APPCAST")"
  [[ "$got_url" == "$want_url" ]] || fail "enclosure url '$got_url', expected '$want_url'"
  SIG="$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$APPCAST")"
  [[ -n "$SIG" ]] || fail "appcast.xml has no sparkle:edSignature"

  # sign_update verifies with the private key file (it has no public-key option).
  SU="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
  [[ -x "$SU" ]] || fail "sign_update not found at $SU"
  "$SU" --verify --ed-key-file "$WORK/seed" "$ZIP" "$SIG" || fail "sign_update --verify rejected the appcast signature"

  rm -f "$WORK/key.pem" "$WORK/seed"
  rm -rf "$ROOT/dist"
  echo "release dry-run ok (arm64-only zip, appcast url + edSignature verified)"
  exit 0
fi

"$ROOT/scripts/bundle.sh"

APP="$ROOT/build/Skitcho.app"
PLIST="$APP/Contents/Info.plist"

[[ -d "$APP/Contents/MacOS" ]] || fail "missing Contents/MacOS"
[[ -x "$APP/Contents/MacOS/Skitcho" ]] || fail "missing executable"
[[ -f "$PLIST" ]] || fail "missing Info.plist"

plist_get() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }
expect_key() {
  local key="$1" want="$2" got
  got="$(plist_get "$key")" || fail "Info.plist key $key missing"
  [[ "$got" == "$want" ]] || fail "Info.plist $key = '$got', expected '$want'"
}

expect_key CFBundleIdentifier com.oleggohman.skitcho
expect_key CFBundleExecutable Skitcho
expect_key LSMinimumSystemVersion 15.0
expect_key LSRequiresNativeExecution true
expect_key CFBundleDocumentTypes:0:LSItemContentTypes:0 public.image
expect_key CFBundleDocumentTypes:0:CFBundleTypeRole Editor
expect_key CFBundleDocumentTypes:1:LSItemContentTypes:0 com.oleggohman.skitcho.document
expect_key CFBundleDocumentTypes:1:CFBundleTypeRole Editor
expect_key CFBundleDocumentTypes:1:LSTypeIsPackage true
expect_key UTExportedTypeDeclarations:0:UTTypeIdentifier com.oleggohman.skitcho.document
expect_key UTExportedTypeDeclarations:0:UTTypeConformsTo:0 com.apple.package
expect_key UTExportedTypeDeclarations:0:UTTypeConformsTo:1 public.composite-content
expect_key UTExportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension:0 skitcho
expect_key SUFeedURL https://github.com/oleggohman/skitcho/releases/latest/download/appcast.xml
expect_key SUEnableAutomaticChecks true
expect_key SUScheduledCheckInterval 86400
expect_key CFBundleIconFile AppIcon
ICNS="$APP/Contents/Resources/AppIcon.icns"
[[ -f "$ICNS" ]] || fail "missing AppIcon.icns in bundle"
ICONSET_DIR="$(mktemp -d)"
iconutil -c iconset "$ICNS" -o "$ICONSET_DIR/AppIcon.iconset" || fail "iconutil cannot read AppIcon.icns"
icon_count="$(find "$ICONSET_DIR/AppIcon.iconset" -name 'icon_*.png' | wc -l | tr -d ' ')"
rm -rf "$ICONSET_DIR"
[[ "$icon_count" == "10" ]] || fail "AppIcon.icns has $icon_count sizes, expected 10"
plist_get SUPublicEDKey >/dev/null || fail "Info.plist key SUPublicEDKey missing"
plist_get CFBundleShortVersionString >/dev/null || fail "CFBundleShortVersionString missing"
plist_get CFBundleVersion >/dev/null || fail "CFBundleVersion missing"

# Every Mach-O must be thin arm64.
macho=0
while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q 'Mach-O'; then
    archs="$(lipo -archs "$f")"
    [[ "$archs" == "arm64" ]] || fail "$f archs '$archs' (expected arm64)"
    macho=$((macho + 1))
  fi
done < <(find "$APP" -type f -print0)
[[ "$macho" -ge 1 ]] || fail "no Mach-O in bundle"

[[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]] || fail "Sparkle.framework not embedded"
otool -l "$APP/Contents/MacOS/Skitcho" | grep -q '@executable_path/../Frameworks' ||
  fail "missing @executable_path/../Frameworks rpath"
if otool -l "$APP/Contents/MacOS/Skitcho" | awk '/cmd LC_RPATH/{r=1} r && $1=="path"{print $2; r=0}' | grep -q '^/'; then
  fail "absolute rpath left in executable"
fi
xpc="$(find "$APP" -name XPCServices -print)"
[[ -z "$xpc" ]] || fail "XPCServices present: $xpc"
selftest="$("$APP/Contents/MacOS/Skitcho" --self-test)" || fail "--self-test exited non-zero"
[[ "$selftest" == "ok" ]] || fail "--self-test printed '$selftest', expected 'ok'"

codesign --verify --deep --strict "$APP" || fail "codesign verification failed"

# No font files in the repo sources or the bundle (system fonts only).
fonts="$(find "$ROOT" \( -path "$ROOT/.build" -o -path "$ROOT/.git" -o -path "$ROOT/.claude" \) -prune -o \
  -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print)"
[[ -z "$fonts" ]] || fail "font files found: $fonts"

# Hex color literals are allowed only in the two token files, or on lines tagged lint:allow-hex.
hex="$(grep -rnE '#[0-9a-fA-F]{6}|Color\(hex:' Sources 2>/dev/null |
  grep -vE '/(AnnotationColor|BrandColor)\.swift:' |
  grep -v 'lint:allow-hex' || true)"
[[ -z "$hex" ]] || fail "hex color literals outside token files: $hex"

echo "test-bundle ok ($macho Mach-O arm64, plist keys, codesign, no fonts, no stray hex)"
