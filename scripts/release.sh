#!/usr/bin/env bash
# Build, sign, (notarize) and package a release: dist/Skitcho-VERSION.dmg + dist/appcast.xml.
# Usage: scripts/release.sh VERSION [--dry-run]
# Env: SIGN_IDENTITY, SPARKLE_PUBLIC_ED_KEY (read by bundle.sh), SPARKLE_ED_PRIVATE_KEY (appcast signing),
#      ASC_KEY_PATH, AppleStoreAPIKey, AppleIssuerID (notarization, skipped with --dry-run),
#      APPCAST_URL (published feed used for merging and the version guards; tests point it at a file:// fixture),
#      FIRST_RELEASE=1 (required when no feed is published yet: only then is a 404 for the feed accepted),
#      MINISIGN_SECRET_KEY (path of the minisign secret key that signs the DMG; required, also with --dry-run),
#      MINISIGN_PUBLIC_KEY_FILE (path of the matching public key, default: minisign.pub at the repository root;
#      only --dry-run may point it elsewhere),
#      MINISIGN_PASSWORD (optional: the minisign key password, for unattended signing; empty counts as unset).
# --dry-run signs ad-hoc and skips notarization. Requires openssl@3 (ed25519) to check the Sparkle key pair
# and minisign. With MINISIGN_PASSWORD set, the password is piped to minisign and no terminal is needed.
# Without it, minisign reads the password from stdin (two prompts: a preflight test signature and the final
# signature after notarization), so a real release then requires stdin to be a terminal.
# Local only: run on the maintainer's Mac, then publish by hand with `gh release create` (see docs/RELEASING.md).
# Secrets are only read from the environment and never printed. Do not add xtrace.
set -euo pipefail

# Keep secrets out of the environment of every child process (dirname, swift build, codesign, notarytool, ...).
# They are passed explicitly: the Sparkle key on stdin, the notarization values as arguments.
# MINISIGN_PASSWORD reaches only minisign, through a pipe from the printf builtin (minisign_sign).
export -n SPARKLE_ED_PRIVATE_KEY AppleStoreAPIKey AppleIssuerID ASC_KEY_PATH MINISIGN_PASSWORD 2>/dev/null || true

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
FIRST_RELEASE="${FIRST_RELEASE:-}"
[[ -z "$FIRST_RELEASE" || "$FIRST_RELEASE" == 1 ]] || fail "FIRST_RELEASE must be unset or 1 (got '$FIRST_RELEASE')"

APP="$ROOT/build/Skitcho.app"
DIST="$ROOT/dist"
DMG="$DIST/Skitcho-$VERSION.dmg"
GA="$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
PREFIX="https://github.com/oleggohman/skitcho/releases/download/v$VERSION/"
APPCAST_URL="${APPCAST_URL:-https://github.com/oleggohman/skitcho/releases/latest/download/appcast.xml}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------------------------------
# Preflight: the inputs, the signing identity and the published feed are checked before building or
# contacting Apple. The notarization credentials themselves can only be checked by notarytool, after the build.
# ---------------------------------------------------------------------------------------------------
[[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]] || fail "SPARKLE_ED_PRIVATE_KEY is not set"
PUBLIC_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
[[ "$PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] ||
  fail "SPARKLE_PUBLIC_ED_KEY must be a 44-character base64 ed25519 public key"

OPENSSL="$(brew --prefix openssl@3 2>/dev/null || true)/bin/openssl"
[[ -x "$OPENSSL" ]] || OPENSSL=openssl # /usr/bin/openssl is LibreSSL and lacks ed25519
# Prints the public key of a Sparkle private key (base64: a 32-byte seed, or the legacy 96-byte form whose
# last 32 bytes are the public key). The key only travels through builtins and pipes, never argv or disk.
derive_public_key() {
  local len
  len="$(printf '%s' "$1" | base64 --decode | wc -c | tr -d ' ')"
  case "$len" in
    32)
      # PKCS#8 DER prefix for a raw ed25519 seed.
      { printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20' &&
        printf '%s' "$1" | base64 --decode; } |
        "$OPENSSL" pkey -inform DER -pubout -outform DER 2>/dev/null | tail -c 32 | base64
      ;;
    96) printf '%s' "$1" | base64 --decode | tail -c 32 | base64 ;;
    *) return 1 ;;
  esac
}
derived="$(derive_public_key "$SPARKLE_ED_PRIVATE_KEY")" || derived=""
[[ -n "$derived" ]] || fail "cannot derive the public key from SPARKLE_ED_PRIVATE_KEY (install openssl@3?)"
[[ "$derived" == "$PUBLIC_KEY" ]] || fail "SPARKLE_PUBLIC_ED_KEY does not match SPARKLE_ED_PRIVATE_KEY"

if [[ "$DRY_RUN" == 0 ]]; then
  [[ -n "${SIGN_IDENTITY:-}" ]] || fail "SIGN_IDENTITY is not set (a release must be Developer ID signed)"
  : "${ASC_KEY_PATH:?ASC_KEY_PATH is not set}" "${AppleStoreAPIKey:?AppleStoreAPIKey is not set}" \
    "${AppleIssuerID:?AppleIssuerID is not set}"
  [[ -f "$ASC_KEY_PATH" ]] || fail "ASC_KEY_PATH does not point to a file"
  # -v lists only valid identities (an expired or revoked certificate is missing). Output captured first:
  # grep -q on a pipe could SIGPIPE the producer under pipefail.
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  grep -qF -- "$SIGN_IDENTITY" <<<"$identities" ||
    fail "SIGN_IDENTITY is not a valid code signing identity in the keychain search list"
else
  SIGN_IDENTITY="" # dry-run is always ad-hoc signed
fi

# minisign: the secret key's id is encrypted, so a test signature verified with the public key is the only way
# to catch a wrong key or password before building and notarizing. Without MINISIGN_PASSWORD, stdin stays
# attached for the password prompt.
command -v minisign >/dev/null 2>&1 || fail "minisign not found (brew install minisign)"
MINISIGN_SECRET_KEY="${MINISIGN_SECRET_KEY:-}"
MINISIGN_PASSWORD="${MINISIGN_PASSWORD:-}"
# Runs `minisign -S "$@"`. With MINISIGN_PASSWORD set, the password is piped from the printf builtin (never
# argv, disk or output); otherwise stdin stays attached for the prompt. MINISIGN_PASSWORD is meant for the
# encrypted key: with an unencrypted key minisign never reads stdin and printf can hit SIGPIPE under pipefail.
minisign_sign() {
  if [[ -n "$MINISIGN_PASSWORD" ]]; then
    printf '%s\n' "$MINISIGN_PASSWORD" | minisign -S "$@"
  else
    minisign -S "$@"
  fi
}
MINISIGN_PUBLIC_KEY_FILE="${MINISIGN_PUBLIC_KEY_FILE:-$ROOT/minisign.pub}"
[[ -n "$MINISIGN_SECRET_KEY" ]] || fail "MINISIGN_SECRET_KEY is not set"
[[ -f "$MINISIGN_SECRET_KEY" && -r "$MINISIGN_SECRET_KEY" ]] ||
  fail "MINISIGN_SECRET_KEY does not point to a readable file"
[[ -f "$MINISIGN_PUBLIC_KEY_FILE" ]] || fail "minisign public key file $MINISIGN_PUBLIC_KEY_FILE not found"
if [[ "$DRY_RUN" == 0 ]]; then
  # A real release verifies only against the committed key that README and SECURITY publish.
  [[ "$MINISIGN_PUBLIC_KEY_FILE" == "$ROOT/minisign.pub" ]] ||
    fail "MINISIGN_PUBLIC_KEY_FILE must be unset for a real release (got '$MINISIGN_PUBLIC_KEY_FILE')"
  # Without MINISIGN_PASSWORD, a password piped into release.sh would be consumed by the test signature and
  # leave the final signature with EOF, so the prompts need a terminal.
  [[ -n "$MINISIGN_PASSWORD" || -t 0 ]] ||
    fail "stdin is not a terminal: minisign needs it for the key password (or set MINISIGN_PASSWORD)"
fi
NONCE="$WORK/minisign-nonce"
printf 'skitcho release %s preflight %s\n' "$VERSION" "$(date +%s)" >"$NONCE"
echo "minisign: test signature (enter the minisign key password if asked)"
if ! minisign_sign -s "$MINISIGN_SECRET_KEY" -m "$NONCE" -x "$NONCE.minisig" ||
  ! minisign -V -q -p "$MINISIGN_PUBLIC_KEY_FILE" -m "$NONCE" -x "$NONCE.minisig"; then
  fail "MINISIGN_SECRET_KEY does not match $MINISIGN_PUBLIC_KEY_FILE (or wrong password / MINISIGN_PASSWORD)"
fi
rm -f "$NONCE" "$NONCE.minisig"

if [[ ! -x "$GA" ]]; then
  swift package resolve >/dev/null
fi
[[ -x "$GA" ]] || fail "generate_appcast not found at $GA"

# bundle.sh derives CFBundleVersion the same way.
if git rev-parse HEAD >/dev/null 2>&1; then
  BUILD_NUMBER="$(git rev-list --count HEAD)"
else
  BUILD_NUMBER="0"
fi

# The published appcast keeps older versions in the feed. 200 merges it. 404 is accepted only with
# FIRST_RELEASE=1: GitHub also answers 404 when the latest release lacks appcast.xml, and dropping the feed
# would lose the update history and skip the version guards. Anything else aborts; the feed is never reset.
rm -rf "$DIST"
mkdir -p "$DIST"
if [[ "$APPCAST_URL" == file://* ]]; then
  curl -fsS "$APPCAST_URL" -o "$DIST/appcast.xml" || fail "cannot read $APPCAST_URL"
else
  code="$(curl -sSL --retry 3 --connect-timeout 15 --max-time 120 -w '%{http_code}' \
    -o "$DIST/appcast.xml" "$APPCAST_URL")" || fail "fetching $APPCAST_URL failed (curl exit $?)"
  case "$code" in
    200) ;;
    404)
      rm -f "$DIST/appcast.xml"
      [[ "$FIRST_RELEASE" == 1 ]] ||
        fail "$APPCAST_URL returned 404; set FIRST_RELEASE=1 only if no release with an appcast exists yet"
      echo "no published appcast (FIRST_RELEASE=1)"
      ;;
    *) fail "fetching $APPCAST_URL returned HTTP $code" ;;
  esac
fi
if [[ -f "$DIST/appcast.xml" && "$FIRST_RELEASE" == 1 ]]; then
  fail "FIRST_RELEASE=1 but a feed is published at $APPCAST_URL; unset it"
fi
if [[ -f "$DIST/appcast.xml" ]]; then
  xmllint --noout "$DIST/appcast.xml" || fail "published appcast.xml does not parse"
  max="$(grep -oE 'sparkle:version(>|=")[0-9]+' "$DIST/appcast.xml" | grep -oE '[0-9]+$' | sort -n | tail -1 || true)"
  if [[ -n "$max" && "$BUILD_NUMBER" -le "$max" ]]; then
    fail "build number $BUILD_NUMBER is not greater than published sparkle:version $max"
  fi
  max_short="$(grep -oE 'sparkle:shortVersionString(>|=")[0-9]+\.[0-9]+\.[0-9]+' "$DIST/appcast.xml" |
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)"
  if [[ -n "$max_short" ]]; then
    if [[ "$VERSION" == "$max_short" || "$(printf '%s\n' "$max_short" "$VERSION" | sort -V | tail -1)" != "$VERSION" ]]; then
      fail "version $VERSION is not greater than published version $max_short"
    fi
  fi
fi

# ---------------------------------------------------------------------------------------------------
# Build and sign the app (inside-out, hardened runtime with a Developer ID; ad-hoc in dry-run).
# ---------------------------------------------------------------------------------------------------
VERSION="$VERSION" SIGN_IDENTITY="$SIGN_IDENTITY" SPARKLE_PUBLIC_ED_KEY="$PUBLIC_KEY" "$ROOT/scripts/bundle.sh"

plist_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$plist_build" == "$BUILD_NUMBER" ]] || fail "CFBundleVersion $plist_build, expected $BUILD_NUMBER"
plist_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")"
[[ "$plist_key" == "$PUBLIC_KEY" ]] || fail "SUPublicEDKey in the built Info.plist does not match the signing key"

# Loads Sparkle under the final signature (library validation applies with the hardened runtime).
selftest="$("$APP/Contents/MacOS/Skitcho" --self-test)" || fail "--self-test of the signed app exited non-zero"
[[ "$selftest" == "ok" ]] || fail "--self-test of the signed app printed '$selftest'"

# ---------------------------------------------------------------------------------------------------
# Disk image: Skitcho.app plus an Applications symlink for drag-to-install.
# ---------------------------------------------------------------------------------------------------
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Skitcho.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -fs HFS+ -format UDZO -srcfolder "$STAGE" -volname Skitcho -ov "$DMG"
rm -rf "$STAGE"

if [[ "$DRY_RUN" == 0 ]]; then
  codesign -f -s "$SIGN_IDENTITY" --timestamp "$DMG"
  codesign --verify --strict "$DMG"

  notary() {
    xcrun notarytool "$@" --key "$ASC_KEY_PATH" --key-id "$AppleStoreAPIKey" --issuer "$AppleIssuerID"
  }
  print_log() {
    local sub_id
    sub_id="$(printf '%s' "$1" | plutil -extract id raw -o - - 2>/dev/null || true)"
    if [[ -n "$sub_id" ]]; then
      notary log "$sub_id" || true
    fi
  }
  result="$(notary submit "$DMG" --wait --timeout 45m --output-format json)" || {
    rc=$?
    print_log "${result:-}"
    fail "notarytool submit failed (exit $rc)"
  }
  status="$(printf '%s' "$result" | plutil -extract status raw -o - - 2>/dev/null || true)"
  if [[ "$status" != "Accepted" ]]; then
    print_log "$result"
    fail "notarization status '$status'"
  fi
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl_out="$(spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 || true)"
  echo "$spctl_out"
  grep -q 'Notarized Developer ID' <<<"$spctl_out" || fail "spctl does not report Notarized Developer ID"
else
  echo "dry-run: ad-hoc signed, skipping DMG signing and notarization"
fi

# ---------------------------------------------------------------------------------------------------
# Appcast: dist/ holds only the final DMG and the fetched feed; the DMG is the Sparkle enclosure.
# ---------------------------------------------------------------------------------------------------
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$GA" --ed-key-file - --maximum-versions 0 \
  --download-url-prefix "$PREFIX" "$DIST"

# ---------------------------------------------------------------------------------------------------
# minisign signature of the final DMG (stapled and in the appcast), published next to it as a release asset.
# With MINISIGN_PASSWORD: one attempt (the preflight already checked the password). Without it, stdin stays
# attached for the password prompt: up to 3 attempts on a terminal, one otherwise.
# ---------------------------------------------------------------------------------------------------
MINISIG="$DMG.minisig"
TRUSTED_COMMENT="Skitcho $VERSION Skitcho-$VERSION.dmg"
attempts=1
if [[ -z "$MINISIGN_PASSWORD" && -t 0 ]]; then
  attempts=3
fi
signed=0
for ((i = 1; i <= attempts; i++)); do
  echo "minisign: signing $(basename "$DMG") (attempt $i of $attempts)"
  if minisign_sign -s "$MINISIGN_SECRET_KEY" -m "$DMG" -x "$MINISIG" -t "$TRUSTED_COMMENT"; then
    signed=1
    break
  fi
done
if [[ "$signed" == 1 ]] && ! minisign -V -q -p "$MINISIGN_PUBLIC_KEY_FILE" -m "$DMG" -x "$MINISIG"; then
  signed=0
fi
if [[ "$signed" != 1 ]]; then
  rm -f "$MINISIG"
  {
    echo "error: minisign signing of $DMG failed."
    echo "dist/ already holds the final DMG and appcast.xml. Do NOT re-run release.sh for $VERSION (it would"
    echo "rebuild and re-notarize a different DMG). Sign by hand, then publish:"
    echo "  minisign -S -s \"$MINISIGN_SECRET_KEY\" -m \"$DMG\" -x \"$MINISIG\" -t \"$TRUSTED_COMMENT\""
    echo "  minisign -V -p \"$MINISIGN_PUBLIC_KEY_FILE\" -m \"$DMG\" -x \"$MINISIG\""
  } >&2
  exit 1
fi

echo "release ok: $DMG + $(basename "$MINISIG") (version $VERSION build $BUILD_NUMBER, dry-run=$DRY_RUN)"
