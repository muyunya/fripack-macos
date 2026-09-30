#!/usr/bin/env bash
#
# Launch a macOS app with a chromatic script injected into it.
#
#   inject-macos-app.sh <App.app> <script.js> [--out DIR] [--keep-running]
#
# Why it takes three steps rather than one:
#
#   macOS honours DYLD_INSERT_LIBRARIES only for processes that are not hardened.
#   Every Electron/CEF app shipped today is signed with the hardened runtime
#   (flags=0x10000(runtime)), and such a process ignores DYLD_* entirely - the
#   library is simply never loaded, with no error anywhere. Re-signing the app
#   ad-hoc drops that flag (flags=0x2(adhoc)) and the injection goes through.
#
#   This edits the app in place. Re-downloading it is the way back. Point it at a
#   copy if that matters.
#
# What you get: the app starts normally, and the script runs inside its main process
# and every helper process it spawns.
#
# One caveat worth knowing before you debug a script that "does nothing": a CEF app's
# stdout is not connected to your terminal, so console.log from the script goes
# nowhere you can see. Have the script write a file instead.
set -euo pipefail

APP=""
SCRIPT=""
OUT=""
KEEP_RUNNING=0

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --keep-running) KEEP_RUNNING=1; shift ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) if [ -z "$APP" ]; then APP="$1"; elif [ -z "$SCRIPT" ]; then SCRIPT="$1"; else echo "unexpected argument: $1" >&2; exit 2; fi; shift ;;
  esac
done

[ -n "$APP" ] && [ -n "$SCRIPT" ] || { echo "usage: $(basename "$0") <App.app> <script.js> [--out DIR] [--keep-running]" >&2; exit 2; }
[ -d "$APP" ] || { echo "not an app bundle: $APP" >&2; exit 1; }
[ -f "$SCRIPT" ] || { echo "no such script: $SCRIPT" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRIPACK_BIN="${FRIPACK_BIN:-$HERE/../fripack/target/release/fripack}"
PAYLOAD_SRC="${PAYLOAD:-$HERE/../chromatic/build/macosx/arm64/releasedbg/libchromatic-injectee.dylib}"
OUT="${OUT:-$(mktemp -d /tmp/chromatic-inject.XXXXXX)}"

[ -x "$FRIPACK_BIN" ] || { echo "fripack not found at $FRIPACK_BIN (set FRIPACK_BIN)" >&2; exit 1; }
[ -f "$PAYLOAD_SRC" ] || { echo "payload not found at $PAYLOAD_SRC (set PAYLOAD)" >&2; exit 1; }

APP_NAME="$(basename "$APP" .app)"
EXEC_NAME="$(defaults read "$APP/Contents/Info.plist" CFBundleExecutable)"
EXEC="$APP/Contents/MacOS/$EXEC_NAME"
[ -x "$EXEC" ] || { echo "no executable at $EXEC" >&2; exit 1; }

echo "==> building a payload that carries $(basename "$SCRIPT")"
mkdir -p "$OUT/build"
cp "$SCRIPT" "$OUT/build/script.js"
cat > "$OUT/build/fripack.json" <<JSON
{
  "app": {
    "type": "shared",
    "platform": "macos-arm64",
    "entry": "./script.js",
    "xz": false,
    "outputDir": "./out",
    "targetBaseName": "$APP_NAME",
    "overridePrebuildFile": "$PAYLOAD_SRC"
  }
}
JSON
( cd "$OUT/build" && "$FRIPACK_BIN" build app ) || exit 1
PAYLOAD="$OUT/build/out/$APP_NAME-macos-arm64.dylib"
[ -f "$PAYLOAD" ] || { echo "the build produced no payload" >&2; exit 1; }

echo "==> dropping the hardened runtime flag on $APP_NAME"
before="$(codesign -dv "$APP" 2>&1 | grep -o 'flags=0x[0-9a-f]*' || echo 'flags=none')"
codesign --remove-signature "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP"
after="$(codesign -dv "$APP" 2>&1 | grep -o 'flags=0x[0-9a-f]*' || echo 'flags=none')"
echo "    $before -> $after"
case "$after" in
  *runtime*) echo "    the runtime flag is still set; injection will be ignored" >&2; exit 1 ;;
esac

echo "==> launching with the payload preloaded"
echo "    payload: $PAYLOAD"
if [ "$KEEP_RUNNING" -eq 1 ]; then
  ( cd "$APP/Contents/MacOS" && DYLD_INSERT_LIBRARIES="$PAYLOAD" "./$EXEC_NAME" > "$OUT/app.log" 2>&1 & echo $! > "$OUT/app.pid" )
  sleep 3
  echo "    pid $(cat "$OUT/app.pid"), log: $OUT/app.log"
else
  ( cd "$APP/Contents/MacOS" && DYLD_INSERT_LIBRARIES="$PAYLOAD" "./$EXEC_NAME" > "$OUT/app.log" 2>&1 & echo $! > "$OUT/app.pid" )
  echo "    pid $(cat "$OUT/app.pid")"
fi
echo "    work directory: $OUT"
