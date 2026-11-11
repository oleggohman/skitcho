#!/usr/bin/env bash
# Build the bundle and assert its structure, architecture, signature and repo hygiene.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

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
