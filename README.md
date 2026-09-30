# fripack-macos

Builds and publishes [fripack](https://github.com/std-microblock/fripack) — a tool
that packages a Frida script into a distributable binary — **for macOS**, together
with the injectable payload it needs.

Upstream has no macOS payload, so `fripack`'s `macos-*` targets cannot download
one. This repository fills that gap: it builds the CLI and the payload, publishes
both as release assets, and documents what actually works on macOS.

> **Status**: the payload is a `.dylib` you inject into a *non-hardened* target
> process. Read [What works on macOS](#what-works-on-macos) before filing a bug —
> most "it does nothing" reports are the hardened-runtime restriction below.

## Quick start

**1. Get the CLI**

```sh
# Apple Silicon
curl -L -o fripack https://github.com/muyunya/fripack-macos/releases/latest/download/fripack-macos-arm64
chmod +x fripack && sudo mv fripack /usr/local/bin/

# Intel
curl -L -o fripack https://github.com/muyunya/fripack-macos/releases/latest/download/fripack-macos-x86_64
chmod +x fripack && sudo mv fripack /usr/local/bin/
```

**2. Point a target at the published payload**

`fripack.json` (replace `<tag>` with the release tag you are using):

```json
{
  "macos": {
    "type": "shared",
    "platform": "macos-arm64",
    "entry": "./main.js",
    "payloadUrl": "https://github.com/muyunya/fripack-macos/releases/download/<tag>/fripack-inject-<tag>-{platform}.{ext}"
  }
}
```

**3. Build**

```sh
fripack build macos
# -> fripack/macos-macos-arm64.dylib
```

The payload is downloaded, your script is embedded into it, and the result is
**re-signed ad-hoc** — patching invalidates the signature and macOS refuses to
load a Mach-O with a broken one.

**4. Load it into a process**

```sh
DYLD_INSERT_LIBRARIES=$PWD/fripack/macos-macos-arm64.dylib /path/to/target
```

## Two payloads

Both are published for each release. They expose the same interface, so the only
difference for you is the `payloadUrl` you point at.

| | `fripack-inject-*` (Frida) | `chromatic-injectee-*` (chromatic) |
|---|---|---|
Engine | Frida's GumJS | chromatic's own QuickJS runtime |
License | **GPL-3.0** (+ LGPL for Frida) — an explicit grant | **none declared upstream** — see [`THIRD_PARTY.md`](THIRD_PARTY.md) |
Build cost in CI | 30-60 min per arch | a few minutes |
Frida API (`Java`, `Interceptor`, …) | full | chromatic's Frida-compatible subset |
Best for | anything you intend to redistribute | personal use, or when you want a much smaller build |

```json
"payloadUrl": "https://github.com/muyunya/fripack-macos/releases/download/<tag>/chromatic-injectee-<tag>-{platform}.{ext}"
```

If licensing matters to you, use the Frida payload.

## What works on macOS

| Situation | Result |
|---|---|
Unsigned / ad-hoc signed / non-hardened target | ✅ injection works |
Hardened runtime target (most shipped apps) | ❌ dyld **silently ignores** `DYLD_INSERT_LIBRARIES`; adding `disable-library-validation` does not help either |
Object files that are already signed by someone else | require re-signing after any modification |

Getting into a hardened-runtime application means modifying and re-signing **that
application**, which is out of scope here. Apple Silicon additionally requires a
valid (at least ad-hoc) signature on the dylib itself; the build step handles it.

## Rebuilding a payload yourself

You do not need to — the releases carry both. But the builds are reproducible:

```sh
./scripts/build-payload.sh arm64            # Frida payload, ~30-60 min, several GB
./scripts/build-chromatic-payload.sh arm64  # chromatic payload, a few minutes

./scripts/verify-payload.sh out/libfripack-inject-macos-arm64.dylib
```

`build-payload.sh` documents every non-obvious requirement (Go >= 1.26,
`MACOS_CERTID=-`, the Frida configure flags, where the devkit has to land). Those
three are the reason the upstream payload project currently publishes nothing for
macOS.

`build-chromatic-payload.sh` works around an xmake package-lock deadlock that
otherwise hangs the configure step: installing `breeze-js-runtime` shells out to a
nested xmake that waits for a lock its own parent holds. The script retries with a
stall watchdog, which makes progress on every attempt.

## How the payload works

The payload exposes two things the CLI patches in place:

* `g_embedded_config` — a small struct the CLI locates by magic bytes;
* a reserved, file-backed section `__DATA,__fripack` the script is written into.

Because both live in the same segment, the CLI only has to compute a
virtual-address delta between them. No Mach-O structure is rewritten, which keeps
the tool simple and makes failures loud instead of producing corrupt binaries.

The one non-obvious requirement on the payload side: the reserved buffer **must
have an explicit initialiser**. Without it the linker folds the buffer into
zerofill, it occupies no space in the file, and there is nowhere to write.

## Licensing

* Code in **this** repository: MIT (`LICENSE`).
* Released binaries bundle third-party components under their own licenses —
  **read [`THIRD_PARTY.md`](THIRD_PARTY.md)**, especially if you plan to
  redistribute the payload (GPL-3.0, and LGPL-2.1 for Frida).

## Layout

```
scripts/build-payload.sh            build the Frida-based payload (GPL-3.0)
scripts/build-chromatic-payload.sh  build the chromatic payload (no upstream license)
scripts/verify-payload.sh           end-to-end check: patch, sign, inject, assert
examples/fripack.json               a ready-to-copy macOS target
.github/workflows/                  builds the CLI and both payloads, publishes releases
```
