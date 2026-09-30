#!/usr/bin/env bash
#
# Builds Fripack.app: a double-clickable front end for the fripack CLI.
#
# Two inputs come from outside this repo, because this repo does not build them:
#
#   FRIPACK_BIN   the fripack CLI (cargo build --release in the fripack checkout)
#   PAYLOAD       the chromatic injectee dylib for macos-arm64
#
# Both have defaults pointing at a sibling checkout, which is what they are during
# development; the release workflow passes the artifacts it just built.
#
# Everything the finished bundle needs lives in Contents/Resources, so the .app can
# be moved anywhere afterwards.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$ROOT/build}"
APP="$OUT/Fripack.app"

FRIPACK_BIN="${FRIPACK_BIN:-$ROOT/../../fripack/target/release/fripack}"
PAYLOAD="${PAYLOAD:-$ROOT/../../chromatic/build/macosx/arm64/releasedbg/libchromatic-injectee.dylib}"

fail() { echo "build-app: $*" >&2; exit 1; }

for tool in swiftc clang codesign plutil; do
  command -v "$tool" >/dev/null || fail "$tool is required (install the command line tools: xcode-select --install)"
done

[ -x "$FRIPACK_BIN" ] || fail "fripack CLI not found at $FRIPACK_BIN — build it with 'cargo build --release', or set FRIPACK_BIN"
[ -f "$PAYLOAD" ] || fail "payload not found at $PAYLOAD — build chromatic, or set PAYLOAD"

echo "==> staging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" \
         "$APP/Contents/Resources/bin" \
         "$APP/Contents/Resources/payload" \
         "$APP/Contents/Resources/demo" \
         "$APP/Contents/Resources/samples"

echo "==> compiling the demo target (this is what the app injects into)"
clang -O1 -Wl,-export_dynamic \
  -o "$APP/Contents/Resources/demo/demo-target" \
  "$ROOT/demo/demo-target.c"

echo "==> copying the toolchain into the bundle"
cp "$FRIPACK_BIN" "$APP/Contents/Resources/bin/fripack"
chmod +x "$APP/Contents/Resources/bin/fripack"

# Stripping is worth it here: the payload carries a debug build's symbols and none of
# them are used for anything, while the app is meant to be handed to someone. The
# resulting bundle is checked by `--run-demo` before it ships, so a strip that damaged
# the payload would not go unnoticed.
cp "$PAYLOAD" "$APP/Contents/Resources/payload/libchromatic-injectee-macos-arm64.dylib"
strip -x "$APP/Contents/Resources/payload/libchromatic-injectee-macos-arm64.dylib" 2>/dev/null \
  || echo "    (strip unavailable, keeping the payload as built)"

cp "$ROOT/samples/hook-demo.js" "$APP/Contents/Resources/samples/hook-demo.js"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> compiling the app"
swiftc -parse-as-library -O \
  -target "$(uname -m)-apple-macos13.0" \
  -o "$APP/Contents/MacOS/Fripack" \
  "$ROOT"/Sources/*.swift

echo "==> checking the bundle"
plutil -lint "$APP/Contents/Info.plist" >/dev/null || fail "Info.plist does not parse"

# Ad-hoc, because there is no developer certificate here. The signature is what makes
# the bundle launchable without a Gatekeeper prompt on the machine that built it.
codesign --force --sign - "$APP" >/dev/null 2>&1 || fail "codesign failed"
codesign --verify --deep --strict "$APP" || fail "the signature does not verify"

echo "==> verifying the pipeline the Run button uses"
"$APP/Contents/MacOS/Fripack" --run-demo > "$OUT/run-demo.log" 2>&1 || true
if grep -q "\[demo\] done" "$OUT/run-demo.log"; then
  echo "    the demo program ran to completion under the payload"
else
  echo "    ---- run-demo.log ----" >&2
  tail -20 "$OUT/run-demo.log" >&2
  fail "--run-demo did not reach the end of the demo program"
fi

echo
echo "$APP"
echo "  size: $(du -sh "$APP" | cut -f1)"
echo "  open it with: open '$APP'"
