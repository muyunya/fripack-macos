#!/usr/bin/env bash
#
# Builds the alternative macOS payload: chromatic's injectee.
#
# Compared with the Frida-based payload this one is much cheaper to build (a few
# minutes instead of 30-60), because it does not have to build an entire
# instrumentation toolkit first - chromatic ships its own engine.
#
# It is built from the fork at muyunya/chromatic, which carries two changes the
# payload needs and upstream does not have yet:
#
#   * a reserved, file-backed __DATA,__fripack section, so the script can be
#     written into the binary without rewriting its Mach-O structure;
#   * a teardown fix - without it the host process aborts on exit, because the
#     cleanup path touches static objects that have already been destroyed.
#
# See THIRD_PARTY.md before redistributing the result: upstream chromatic
# declares no license.
#
# Usage:
#   ./scripts/build-chromatic-payload.sh [arm64|x86_64]
#
# Env:
#   WORK             scratch directory      (default ./.work-chromatic)
#   OUT              where the .dylib lands (default ./out-chromatic)
#   CHROMATIC_REPO   source to build        (default muyunya/chromatic)
set -euo pipefail

ARCH="${1:-$(uname -m)}"
case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "usage: $0 [arm64|x86_64]" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$ROOT/.work-chromatic}"
OUT="${OUT:-$ROOT/out-chromatic}"
REPO="${CHROMATIC_REPO:-https://github.com/muyunya/chromatic.git}"

mkdir -p "$WORK" "$OUT"
cd "$WORK"

if [ ! -d chromatic ]; then
  echo "==> cloning $REPO"
  git clone --depth 1 "$REPO" chromatic
fi
# Absolute paths from here on: a relative `cd ../..` out of src/core/typescript
# lands in src/, not the repository root, and xmake then silently builds from the
# wrong directory.
CHROMATIC="$WORK/chromatic"

# ── TypeScript bundle (get baked into the binary) ─────────────────────────────
echo "==> building the TypeScript bundle"
cd "$CHROMATIC/src/core/typescript"
pnpm install --frozen-lockfile 2>/dev/null || true
# pnpm refuses to purge a pre-existing node_modules without a TTY unless it is
# told that non-interactive is fine. CI sets CI=true already; local runs do not.
CI="${CI:-true}" pnpm install
CI="${CI:-true}" pnpm build
cd "$CHROMATIC"

# ── Native build ──────────────────────────────────────────────────────────────
#
# xmake can deadlock while installing packages here: installing breeze-js-runtime
# shells out to a nested xmake, which then waits for a package lock its own
# parent holds. Retrying makes progress every time (already-installed packages
# are reused and the window shrinks), so retry until it gets through.
configure_with_retry() {
  local attempt log=/tmp/chromatic-configure.$$.log
  for attempt in 1 2 3 4 5 6; do
    echo "==> xmake configure (attempt $attempt)"
    xmake f -m releasedbg -y >"$log" 2>&1 &
    local pid=$! last=0 stall=0
    while kill -0 "$pid" 2>/dev/null; do
      sleep 10
      local size
      size=$(wc -c <"$log" 2>/dev/null || echo 0)
      if [ "$size" = "$last" ]; then stall=$((stall + 1)); else stall=0; last=$size; fi
      if [ "$stall" -ge 12 ]; then
        echo "    stalled for 120s (package lock deadlock), retrying"
        pkill -9 -P "$pid" 2>/dev/null || true
        kill -9 "$pid" 2>/dev/null || true
        break
      fi
    done
    wait "$pid" 2>/dev/null && { rm -f "$log"; return 0; }
  done
  echo "configure kept failing; last log:" >&2
  tail -30 "$log" >&2
  rm -f "$log"
  return 1
}

configure_with_retry
echo "==> building chromatic-injectee"
xmake build -y chromatic-injectee

# Exclude the .dSYM bundle: it contains a file with the same name, and copying
# that instead of the dylib would produce a "payload" that is a debug object.
DYLIB="$(find build -name 'libchromatic-injectee.dylib' -not -path '*.dSYM/*' | head -1)"
[ -n "$DYLIB" ] || { echo "no dylib produced" >&2; exit 1; }

DEST="$OUT/libchromatic-injectee-macos-$ARCH.dylib"
cp "$DYLIB" "$DEST"

echo
echo "==> built $DEST"
echo "==> reserved section (fripack writes the script here):"
otool -l "$DEST" | awk '/sectname __fripack/{f=1} f&&/segname|addr |size |flags /{print "   "$0} f&&/Load command/{exit}' | head -5
echo "==> verify it with scripts/verify-payload.sh"
