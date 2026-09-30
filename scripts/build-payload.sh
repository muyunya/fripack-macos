#!/usr/bin/env bash
#
# Builds the macOS payload (libfripack-inject.dylib) from scratch.
#
# This is the recipe this repository's CI runs. It is fiddly for three reasons,
# all of which are also why upstream publishes nothing for macOS:
#
#   1. Frida's build needs Go >= 1.26 (upstream CI pins 1.25, which no longer
#      works: "Need Go >= 1.26 to build the Compiler backend ...").
#   2. Frida signs the helper and agent it builds. Without an identity it aborts
#      with "MACOS_CERTID not set", so we sign ad-hoc.
#   3. The gumjs devkit is not a downloadable package: it has to be built and
#      copied into the payload source tree before xmake runs.
#
# Usage:
#   ./scripts/build-payload.sh [arm64|x86_64]
#
# Env:
#   WORK        scratch directory                    (default ./.work)
#   OUT         where the .dylib ends up             (default ./out)
#   PAYLOAD_REPO  payload source to build            (default muyunya/fripack-inject)
set -euo pipefail

ARCH="${1:-$(uname -m)}"
case "$ARCH" in
  arm64)  HOST=macos-arm64;  XMAKE_ARCH=arm64 ;;
  x86_64) HOST=macos-x86_64; XMAKE_ARCH=x64 ;;
  *) echo "usage: $0 [arm64|x86_64]" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$ROOT/.work}"
OUT="${OUT:-$ROOT/out}"
PAYLOAD_REPO="${PAYLOAD_REPO:-https://github.com/muyunya/fripack-inject.git}"

mkdir -p "$WORK" "$OUT"
cd "$WORK"

echo "==> target: $HOST (xmake arch $XMAKE_ARCH)"

# ── 1. Go ─────────────────────────────────────────────────────────────────────
if ! command -v go >/dev/null 2>&1 || [ "$(go env GOVERSION 2>/dev/null | sed 's/go1\.//;s/\..*//')" -lt 26 ] 2>/dev/null; then
  echo "==> installing Go >= 1.26 into $WORK/go"
  GO_VER=1.27.1
  curl -sL -o go.tar.gz "https://go.dev/dl/go${GO_VER}.darwin-${ARCH}.tar.gz"
  rm -rf go && tar -xzf go.tar.gz
  export GOROOT="$WORK/go"
  export PATH="$GOROOT/bin:$PATH"
fi
echo "==> go $(go version | awk '{print $3}')"

# ── 2. Python deps Frida's build wants ────────────────────────────────────────
if [ ! -d venv ]; then python3 -m venv venv; fi
./venv/bin/pip install -q --upgrade pip setuptools wheel
./venv/bin/pip install -q lief graphlib requests
export PATH="$WORK/venv/bin:$PATH"

# ── 3. Frida + patches ────────────────────────────────────────────────────────
if [ ! -d fripack-inject ]; then
  git clone --depth 1 "$PAYLOAD_REPO" fripack-inject
fi
PATCHROOT="$WORK/fripack-inject/patches"

if [ ! -d frida ]; then
  echo "==> cloning frida (large; this is the slow part)"
  git clone --recurse-submodules https://github.com/frida/frida.git
fi

if [ ! -f frida/.patched ]; then
  echo "==> applying patches"
  cd frida
  git config user.name  "fripack-macos"
  git config user.email "fripack-macos@localhost"
  for path in "$PATCHROOT"/*; do
    name="$(basename "$path")"
    cd "subprojects/$name"
    for file in $(ls "$PATCHROOT/$name/" | sort); do
      full="$PATCHROOT/$name/$file"
      case "$file" in
        *.patch) git am "$full" >/dev/null || { echo "patch failed: $name/$file" >&2; exit 1; } ;;
        *.js)    node "$full" ;;
      esac
    done
    cd ../..
  done
  touch .patched
  cd ..
fi

# ── 4. Build Frida, ad-hoc signed ─────────────────────────────────────────────
export MACOS_CERTID=-          # without this: "MACOS_CERTID not set" -> abort
mkdir -p "build-$HOST"
cd "build-$HOST"
if [ ! -f build.ninja ]; then
  "../frida/configure" --prefix=./installdir --host="$HOST" -- \
    -Dfrida-gum:devkits=gum,gumjs \
    -Dfrida-gum:v8=disabled \
    -Dfrida-gum:database=disabled \
    -Dfrida-gum:tests=disabled \
    -Dfrida-core:compiler_backend=enabled \
    -Dfrida-core:devkits=core
fi
make -j"$(sysctl -n hw.ncpu)"
cd ..

# ── 5. Hand the devkit to the payload build ───────────────────────────────────
DEVKIT="build-$HOST/subprojects/frida-gum/bindings/gumjs/devkit"
cp build-"$HOST"/subprojects/frida-gum/gum/gumenumtypes.h "$DEVKIT/gumenumtypes.h"
mkdir -p fripack-inject/fripack-inject/frida-gumjs-devkit
cp "$DEVKIT"/* fripack-inject/fripack-inject/frida-gumjs-devkit/

# ── 6. Build the payload ──────────────────────────────────────────────────────
cd fripack-inject/fripack-inject
xmake f -p macosx -a "$XMAKE_ARCH" -y
xmake -y

DYLIB="$(find build -name 'libfripack-inject.dylib' | head -1)"
[ -n "$DYLIB" ] || { echo "no dylib produced" >&2; exit 1; }
cp "$DYLIB" "$OUT/libfripack-inject-$HOST.dylib"

echo
echo "==> built $OUT/libfripack-inject-$HOST.dylib"
otool -l "$OUT/libfripack-inject-$HOST.dylib" | awk '/sectname __fripack/,/^$/' | grep -E 'sectname|segname|size|flags'
echo "==> verify it with scripts/verify-payload.sh"
