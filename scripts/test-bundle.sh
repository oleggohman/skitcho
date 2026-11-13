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
  MNT="$WORK/mnt"
  MOUNTED=0
  cleanup() {
    # Always detach the image before removing the mount point.
    if [[ "$MOUNTED" == 1 ]]; then
      hdiutil detach -quiet "$MNT" || hdiutil detach -quiet -force "$MNT" || true
    fi
    rm -rf "$WORK"
  }
  trap cleanup EXIT
  OPENSSL="$(brew --prefix openssl@3 2>/dev/null || true)/bin/openssl"
  [[ -x "$OPENSSL" ]] || OPENSSL=openssl # /usr/bin/openssl is LibreSSL and may lack ed25519
  "$OPENSSL" genpkey -algorithm ed25519 -out "$WORK/key.pem" 2>/dev/null ||
    fail "$OPENSSL cannot generate ed25519 keys (install openssl@3: brew install openssl@3)"
  "$OPENSSL" pkey -in "$WORK/key.pem" -outform DER | tail -c 32 | base64 >"$WORK/seed"
  PUB="$("$OPENSSL" pkey -in "$WORK/key.pem" -pubout -outform DER | tail -c 32 | base64)"
  "$OPENSSL" genpkey -algorithm ed25519 -out "$WORK/other.pem" 2>/dev/null
  OTHER_PUB="$("$OPENSSL" pkey -in "$WORK/other.pem" -pubout -outform DER | tail -c 32 | base64)"

  # Throwaway unencrypted minisign pairs (-W: no password, so nothing can block on a prompt). Explicit paths
  # keep them away from the committed minisign.pub and from ~/.minisign.
  command -v minisign >/dev/null 2>&1 || fail "minisign not found (brew install minisign)"
  minisign -G -W -p "$WORK/good.pub" -s "$WORK/good.key" </dev/null >/dev/null ||
    fail "minisign cannot generate a key pair"
  minisign -G -W -p "$WORK/other.pub" -s "$WORK/other.key" </dev/null >/dev/null ||
    fail "minisign cannot generate a key pair"
  # The dry run must never touch the committed public key.
  pub_sum() {
    if [[ -f "$ROOT/minisign.pub" ]]; then shasum -a 256 "$ROOT/minisign.pub"; else echo absent; fi
  }
  PUB_SUM_BEFORE="$(pub_sum)"

  DRY_VERSION="9.9.9"
  # Only the cases below set these; a maintainer's real values must never reach the dry run.
  unset FIRST_RELEASE MINISIGN_SECRET_KEY MINISIGN_PUBLIC_KEY_FILE
  # Hermetic feed: a fixture stands in for the published appcast (never the production URL).
  fixture() { # $1 = sparkle:version, $2 = shortVersionString; prints a file:// URL
    cat >"$WORK/appcast-$1-$2.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Skitcho</title>
    <item>
      <title>$2</title>
      <pubDate>Mon, 01 Jan 2024 00:00:00 +0000</pubDate>
      <sparkle:version>$1</sparkle:version>
      <sparkle:shortVersionString>$2</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/oleggohman/skitcho/releases/download/v$2/Skitcho-$2.dmg" length="1" type="application/octet-stream" sparkle:edSignature="AAAA"/>
    </item>
  </channel>
</rss>
XML
    echo "file://$WORK/appcast-$1-$2.xml"
  }
  # $1 = public key, $2 = appcast URL; output goes to $WORK/release.log. Env prefixes on the call (FIRST_RELEASE,
  # MINISIGN_SECRET_KEY, MINISIGN_PUBLIC_KEY_FILE) reach release.sh; the minisign ones default to the good pair
  # (an empty MINISIGN_SECRET_KEY stays empty). stdin is /dev/null so a password prompt can never block.
  run_release() {
    SPARKLE_ED_PRIVATE_KEY="$(cat "$WORK/seed")" SPARKLE_PUBLIC_ED_KEY="$1" SIGN_IDENTITY="" APPCAST_URL="$2" \
      MINISIGN_SECRET_KEY="${MINISIGN_SECRET_KEY-$WORK/good.key}" \
      MINISIGN_PUBLIC_KEY_FILE="${MINISIGN_PUBLIC_KEY_FILE-$WORK/good.pub}" \
      "$ROOT/scripts/release.sh" "$DRY_VERSION" --dry-run </dev/null >"$WORK/release.log" 2>&1
  }
  expect_reject() { # $1 = label, $2 = expected error text, rest = run_release args
    local label="$1" want="$2"
    shift 2
    if run_release "$@"; then
      fail "release.sh accepted $label"
    fi
    grep -qF "$want" "$WORK/release.log" || {
      cat "$WORK/release.log" >&2
      fail "$label: missing '$want'"
    }
    if grep -q 'bundle ok' "$WORK/release.log"; then
      fail "$label was rejected only after building"
    fi
    echo "ok: preflight rejects $label"
  }
  OLD_FEED="$(fixture 1 0.0.1)"
  expect_reject "an empty public key" "SPARKLE_PUBLIC_ED_KEY must be" "" "$OLD_FEED"
  expect_reject "a mismatched public key" "does not match SPARKLE_ED_PRIVATE_KEY" "$OTHER_PUB" "$OLD_FEED"
  expect_reject "a build number not above the feed" "is not greater than published sparkle:version" \
    "$PUB" "$(fixture 999999 0.0.1)"
  expect_reject "a version not above the feed" "is not greater than published version" \
    "$PUB" "$(fixture 1 10.0.0)"
  expect_reject "an unreadable feed" "cannot read" "$PUB" "file://$WORK/missing.xml"
  FIRST_RELEASE=1 expect_reject "FIRST_RELEASE=1 with a published feed" "FIRST_RELEASE=1 but a feed is published" \
    "$PUB" "$OLD_FEED"
  FIRST_RELEASE=yes expect_reject "a FIRST_RELEASE other than 1" "FIRST_RELEASE must be unset or 1" \
    "$PUB" "$OLD_FEED"
  MINISIGN_SECRET_KEY="" expect_reject "an unset MINISIGN_SECRET_KEY" "MINISIGN_SECRET_KEY is not set" \
    "$PUB" "$OLD_FEED"
  MINISIGN_SECRET_KEY="$WORK/missing.key" expect_reject "a missing minisign key file" \
    "MINISIGN_SECRET_KEY does not point to a readable file" "$PUB" "$OLD_FEED"
  MINISIGN_SECRET_KEY="$WORK/other.key" expect_reject "a minisign key not matching the public key" \
    "does not match" "$PUB" "$OLD_FEED"
  rm -rf "$ROOT/dist"
  if ! run_release "$PUB" "$OLD_FEED"; then
    cat "$WORK/release.log" >&2
    fail "release.sh --dry-run failed"
  fi
  tail -n 2 "$WORK/release.log"

  DMG="$ROOT/dist/Skitcho-$DRY_VERSION.dmg"
  APPCAST="$ROOT/dist/appcast.xml"
  [[ -f "$DMG" ]] || fail "missing $DMG"
  [[ -f "$APPCAST" ]] || fail "missing appcast.xml"
  MINISIG="$DMG.minisig"
  [[ -f "$MINISIG" ]] || fail "missing $MINISIG"
  extra="$(find "$ROOT/dist" -mindepth 1 ! -name "Skitcho-$DRY_VERSION.dmg" ! -name "Skitcho-$DRY_VERSION.dmg.minisig" \
    ! -name appcast.xml -print)"
  [[ -z "$extra" ]] || fail "unexpected files in dist: $extra"

  # The minisign signature verifies with the dry-run public key, carries the trusted comment, and fails with
  # any other key.
  minisign -V -q -p "$WORK/good.pub" -m "$DMG" -x "$MINISIG" </dev/null || fail "minisign -V rejected the DMG"
  echo "ok: minisign -V accepts the DMG signature"
  comment="$(minisign -V -Q -p "$WORK/good.pub" -m "$DMG" -x "$MINISIG" </dev/null)" ||
    fail "minisign -V -Q failed"
  [[ "$comment" == "Skitcho $DRY_VERSION Skitcho-$DRY_VERSION.dmg" ]] ||
    fail "minisign trusted comment '$comment', expected 'Skitcho $DRY_VERSION Skitcho-$DRY_VERSION.dmg'"
  echo "ok: minisign trusted comment '$comment'"
  if minisign -V -q -p "$WORK/other.pub" -m "$DMG" -x "$MINISIG" </dev/null 2>/dev/null; then
    fail "minisign -V accepted the DMG signature with another public key"
  fi
  echo "ok: minisign -V rejects another public key"
  [[ "$(pub_sum)" == "$PUB_SUM_BEFORE" ]] || fail "the dry run changed the committed minisign.pub"
  echo "ok: committed minisign.pub unchanged"
  dmg_info="$(hdiutil imageinfo "$DMG" 2>/dev/null)" || fail "dmg: hdiutil imageinfo failed"
  grep -q 'Format: UDZO' <<<"$dmg_info" || fail "dmg: not a UDZO image"
  echo "ok: dmg is UDZO"

  # The DMG mounts read-only and holds an arm64-only, validly signed app plus the Applications link.
  mkdir -p "$MNT"
  MOUNTED=1 # set first: a partly failed attach is still detached by cleanup
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" "$DMG" || fail "dmg: hdiutil attach failed"
  vol="$(diskutil info "$MNT" | awk -F': *' '/Volume Name/{print $2}')"
  [[ "$vol" == "Skitcho" ]] || fail "dmg: volume name '$vol', expected 'Skitcho'"
  echo "ok: dmg volume name Skitcho"
  [[ -d "$MNT/Skitcho.app" ]] || fail "dmg: Skitcho.app missing"
  echo "ok: dmg contains Skitcho.app"
  [[ -L "$MNT/Applications" && "$(readlink "$MNT/Applications")" == "/Applications" ]] ||
    fail "dmg: Applications symlink missing or wrong"
  echo "ok: dmg Applications -> /Applications"
  dmacho=0
  while IFS= read -r -d '' f; do
    if file -b "$f" | grep -q 'Mach-O'; then
      [[ "$(lipo -archs "$f")" == "arm64" ]] || fail "dmg: $f is not thin arm64"
      dmacho=$((dmacho + 1))
    fi
  done < <(find "$MNT/Skitcho.app" -type f -print0)
  [[ "$dmacho" -ge 1 ]] || fail "dmg: no Mach-O found"
  echo "ok: dmg has $dmacho Mach-O, all thin arm64"
  codesign --verify --deep --strict "$MNT/Skitcho.app" || fail "dmg: codesign verification failed"
  echo "ok: dmg app passes codesign --verify --deep --strict"
  dpub="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$MNT/Skitcho.app/Contents/Info.plist")"
  [[ "$dpub" == "$PUB" ]] || fail "dmg: SUPublicEDKey does not match the dry-run key"
  echo "ok: dmg SUPublicEDKey matches the dry-run key"
  hdiutil detach -quiet "$MNT" || fail "dmg: hdiutil detach failed"
  MOUNTED=0

  # appcast.xml parses, keeps the fixture item, and its new item has an edSignature and the DMG URL.
  xmllint --noout "$APPCAST" || fail "appcast.xml does not parse"
  items="$(xmllint --xpath 'count(//item)' "$APPCAST")"
  [[ "$items" == "2" ]] || fail "appcast.xml has $items items, expected 2 (fixture merged)"
  item="//item[*[local-name()='shortVersionString']='$DRY_VERSION']/*[local-name()='enclosure']"
  want_url="https://github.com/oleggohman/skitcho/releases/download/v$DRY_VERSION/Skitcho-$DRY_VERSION.dmg"
  got_url="$(xmllint --xpath "string($item/@url)" "$APPCAST")"
  [[ "$got_url" == "$want_url" ]] || fail "enclosure url '$got_url', expected '$want_url'"
  [[ "$got_url" == *.dmg ]] || fail "enclosure url does not end in .dmg"
  echo "ok: appcast enclosure $got_url"
  SIG="$(xmllint --xpath "string($item/@*[local-name()='edSignature'])" "$APPCAST")"
  [[ -n "$SIG" ]] || fail "appcast.xml has no sparkle:edSignature"

  # sign_update verifies with the private key file (it has no public-key option).
  SU="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
  [[ -x "$SU" ]] || fail "sign_update not found at $SU"
  "$SU" --verify --ed-key-file "$WORK/seed" "$DMG" "$SIG" || fail "sign_update --verify rejected the appcast signature"
  echo "ok: sign_update --verify accepts the DMG signature"

  rm -f "$WORK/key.pem" "$WORK/other.pem" "$WORK/seed" "$WORK/good.key" "$WORK/other.key"
  rm -rf "$ROOT/dist"
  echo "release dry-run ok (UDZO dmg: Skitcho.app + Applications link, arm64-only, appcast url + edSignature," \
    "minisign signature)"
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
expect_key CFBundleDocumentTypes:0:LSHandlerRank Alternate
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
# Captured first: grep -q on a pipe could SIGPIPE otool and fail the pipeline under pipefail.
load_cmds="$(otool -l "$APP/Contents/MacOS/Skitcho")"
rpath_list="$(awk '/cmd LC_RPATH/{r=1} r && $1=="path"{print $2; r=0}' <<<"$load_cmds")"
grep -qxF '@executable_path/../Frameworks' <<<"$rpath_list" ||
  fail "missing @executable_path/../Frameworks rpath"
if grep -q '^/' <<<"$rpath_list"; then
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
