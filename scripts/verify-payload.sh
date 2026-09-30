#!/usr/bin/env bash
#
# End-to-end check for a macOS payload: patch it with fripack, confirm it is
# re-signed, inject it into a throwaway host process, and assert that the
# embedded script actually ran and that the host exited cleanly.
#
# Usage:
#   ./scripts/verify-payload.sh <payload.dylib>
#
# Env:
#   FRIPACK   path to the fripack CLI   (default: `fripack` on PATH)
set -euo pipefail

PAYLOAD="${1:-}"
[ -n "$PAYLOAD" ] || { echo "usage: $0 <payload.dylib>" >&2; exit 2; }
[ -f "$PAYLOAD" ] || { echo "no such file: $PAYLOAD" >&2; exit 1; }
PAYLOAD="$(cd "$(dirname "$PAYLOAD")" && pwd)/$(basename "$PAYLOAD")"

FRIPACK="${FRIPACK:-fripack}"
command -v "$FRIPACK" >/dev/null 2>&1 || [ -x "$FRIPACK" ] || {
  echo "fripack not found; build it or set FRIPACK=" >&2; exit 1; }

case "$(uname -m)" in
  arm64)  PLATFORM=macos-arm64 ;;
  x86_64) PLATFORM=macos-x86_64 ;;
  *) echo "unsupported host arch" >&2; exit 1 ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

cat > host.c <<'C'
#include <stdio.h>
#include <unistd.h>
int main(void) { printf("[host] pid=%d\n", getpid()); fflush(stdout); sleep(1); printf("[host] done\n"); return 0; }
C
clang -o host host.c

cat > main.js <<'JS'
console.log("[verify] JS RUNNING platform=" + Process.platform +
            " arch=" + Process.arch +
            " modules=" + Process.enumerateModules().length);
JS

cat > fripack.json <<JSON
{
  "macos": {
    "type": "shared",
    "platform": "$PLATFORM",
    "entry": "./main.js",
    "xz": false,
    "outputDir": "./out",
    "targetBaseName": "verify",
    "overridePrebuildFile": "$PAYLOAD"
  }
}
JSON

echo "== patching with fripack =="
"$FRIPACK" build macos 2>&1 | grep -E "Patched|Re-signing|Successfully built shared" || true

OUT="out/verify-$PLATFORM.dylib"
[ -f "$OUT" ] || { echo "FAIL: no artifact produced" >&2; exit 1; }

echo "== signature =="
SIG="$(codesign -dvvv "$OUT" 2>&1 || true)"
case "$SIG" in
  *adhoc*) echo "   ad-hoc signed" ;;
  *) echo "FAIL: artifact is not ad-hoc signed" >&2; echo "$SIG" >&2; exit 1 ;;
esac

echo "== injecting =="
DYLD_INSERT_LIBRARIES="$PWD/$OUT" ./host > run.log 2>&1
STATUS=$?
cat run.log

[ "$STATUS" -eq 0 ] || { echo "FAIL: host exited $STATUS (a teardown crash?)" >&2; exit 1; }
grep -q "verify.*JS RUNNING" run.log || { echo "FAIL: embedded script did not run" >&2; exit 1; }

echo "PASS: payload runs, and the host exits cleanly"
