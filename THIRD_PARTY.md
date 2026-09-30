# Third-party components

This repository contains only build scripts, CI and documentation (MIT — see
`LICENSE`). The **release assets it publishes bundle third-party code under
other licenses**, listed here. Read this before redistributing those binaries.

## What the releases contain

| Asset | Built from | License |
|---|---|---|
| `fripack-macos-<arch>` | [`muyunya/fripack`](https://github.com/muyunya/fripack) (a fork of `std-microblock/fripack`) | MIT |
| `fripack-inject-<tag>-macos-<arch>.dylib` | [`muyunya/fripack-inject`](https://github.com/muyunya/fripack-inject) (a fork of `FriRebuild/fripack-inject`) **statically linking Frida** | GPL-3.0 **and** LGPL-2.1-or-later |

## fripack — MIT

Upstream: <https://github.com/std-microblock/fripack>

`fripack` declares `license = "MIT"` in `Cargo.toml` (the upstream repository
has no `LICENSE` file, but the declaration in the manifest is the grant). The
fork at `muyunya/fripack` carries the macOS support this project needs.

Redistributing the CLI therefore just requires keeping the MIT notice and
attribution.

## fripack-inject — GPL-3.0

Upstream: <https://github.com/FriRebuild/fripack-inject> (LICENSE: GPL-3.0)

The macOS payload is built from the fork
[`muyunya/fripack-inject`](https://github.com/muyunya/fripack-inject). That
repository is the **corresponding source** for the payload binaries published
here, as required by GPL-3.0 §6.

If you redistribute the payload, you must:

* pass on the GPL-3.0 license text,
* make the corresponding source available (the fork above, at the exact commit
  the asset was built from — see the release notes),
* not add restrictions beyond the GPL.

The builds are reproducible with `scripts/build-payload.sh`, which is exactly
what CI runs.

## Frida — LGPL-2.1-or-later

Upstream: <https://github.com/frida/frida>

The payload links Frida's runtime (`libfrida-gumjs.a`) **statically**, because
that is the point of the project: a self-contained injectable library. LGPL-2.1
§6 requires that recipients be able to relink the work against a modified
Frida. To satisfy that, this repository publishes:

* the exact build recipe (`scripts/build-payload.sh`),
* the patches applied to Frida (they live in the fripack-inject fork under
  `patches/`),
* the resulting object files / static library on request — open an issue.

Frida itself is not modified in any way that changes its license.

## Not included: chromatic

<https://github.com/std-microblock/chromatic> has **no license file and no
license declaration**, so it is "all rights reserved" by default. Nothing built
from it is published here.

There is a second macOS payload path based on chromatic's injectee, and it works
(see the notes in `docs/`), but it can only be built locally for personal use
until upstream adds a license. If you want that path to be distributable, the
cleanest fix is to ask upstream for a `LICENSE` — it is a one-line change on
their side.

## GitHub Actions runners

The CI uses the standard GitHub-hosted macOS runners. No third-party actions
beyond `actions/*` are used, so there is nothing else to attribute.
