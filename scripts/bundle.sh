#!/usr/bin/env bash
# Assemble build/Skitcho.app (arm64 only), sign it and assert every Mach-O is thin arm64.
# Env: VERSION (default 0.0.0), SIGN_IDENTITY (default ad-hoc), SPARKLE_PUBLIC_ED_KEY (default empty).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "error: Skitcho builds on Apple silicon only (uname -m = $(uname -m))" >&2
  exit 1
fi
if [[ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" == "1" ]]; then
  echo "error: running under Rosetta translation; use a native arm64 shell" >&2
  exit 1
fi

SHORT_VERSION="${VERSION:-0.0.0}"
if git rev-parse HEAD >/dev/null 2>&1; then
  BUILD_VERSION="$(git rev-list --count HEAD)"
else
  BUILD_VERSION="0"
fi
PUBLIC_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

APP="$ROOT/build/Skitcho.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Skitcho" "$APP/Contents/MacOS/Skitcho"

sed -e "s|@SHORT_VERSION@|$SHORT_VERSION|g" \
  -e "s|@BUILD_VERSION@|$BUILD_VERSION|g" \
  -e "s|@SPARKLE_PUBLIC_ED_KEY@|$PUBLIC_KEY|g" \
  Resources/Info.plist.template >"$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundles, if any target declares resources.
shopt -s nullglob
for b in "$BIN_DIR"/*.bundle; do
  cp -R "$b" "$APP/Contents/Resources/"
done
shopt -u nullglob

# 1. Embed Sparkle (ditto keeps the Versions/Current symlinks); no headers, dSYMs or PackageFrameworks.
FW="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN_DIR/Sparkle.framework" "$FW"
# Dangling symlinks fail codesign --strict, so remove both the top-level links and Versions/B copies.
for d in Headers PrivateHeaders Modules; do
  rm -rf "${FW:?}/$d" "${FW:?}/Versions/B/$d"
done

# 2. XPC services are only needed by sandboxed apps; Skitcho is not sandboxed.
rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"

# 3. Thin the Sparkle Mach-Os to arm64 in place (skip any that are already thin arm64).
for m in Sparkle Autoupdate Updater.app/Contents/MacOS/Updater; do
  if [[ "$(lipo -archs "$FW/Versions/B/$m")" != "arm64" ]]; then
    lipo -thin arm64 "$FW/Versions/B/$m" -output "$FW/Versions/B/$m"
  fi
done

# 4. Resolve Sparkle through the bundle and drop absolute toolchain rpaths.
EXE="$APP/Contents/MacOS/Skitcho"
rpaths() { otool -l "$EXE" | awk '/cmd LC_RPATH/{r=1} r && $1=="path"{print $2; r=0}'; }
# Captured first: grep -q on a pipe could SIGPIPE the producer and fail the pipeline under pipefail.
if ! grep -qxF '@executable_path/../Frameworks' <<<"$(rpaths)"; then
  install_name_tool -add_rpath @executable_path/../Frameworks "$EXE"
fi
while IFS= read -r rp; do
  if [[ "$rp" == /* ]]; then
    install_name_tool -delete_rpath "$rp" "$EXE"
  fi
done < <(rpaths)

# 5. Sign inside-out (never --deep when signing).
sign() {
  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign -f -s "$SIGN_IDENTITY" -o runtime --timestamp "$@"
  else
    codesign -f -s - "$@"
  fi
}
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign "$APP"

# 6. Verify.
codesign --verify --deep --strict "$APP"

# Assert every Mach-O in the app is thin arm64.
count=0
while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q 'Mach-O'; then
    archs="$(lipo -archs "$f")"
    if [[ "$archs" != "arm64" ]]; then
      echo "error: $f has archs '$archs', expected 'arm64'" >&2
      exit 1
    fi
    count=$((count + 1))
  fi
done < <(find "$APP" -type f -print0)
if [[ "$count" -lt 1 ]]; then
  echo "error: no Mach-O found in $APP" >&2
  exit 1
fi

echo "bundle ok: $APP (version $SHORT_VERSION build $BUILD_VERSION, $count Mach-O arm64)"
