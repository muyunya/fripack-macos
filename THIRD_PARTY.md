# Third-party components

This repository contains only build scripts, CI and documentation (MIT — see
`LICENSE`). The **release assets it publishes bundle third-party code under
other licenses**, listed here. Read this before redistributing those binaries.

## What the releases contain

| Asset | Built from | License |
|---|---|---|
| `fripack-macos-<arch>` | [`muyunya/fripack`](https://github.com/muyunya/fripack) (a fork of `std-microblock/fripack`) | MIT |
| `fripack-inject-<tag>-macos-<arch>.dylib` | [`muyunya/fripack-inject`](https://github.com/muyunya/fripack-inject) (a fork of `FriRebuild/fripack-inject`) **statically linking Frida** | GPL-3.0 **and** LGPL-2.1-or-later |
| `chromatic-injectee-<tag>-macos-<arch>.dylib` | [`muyunya/chromatic`](https://github.com/muyunya/chromatic) (a fork of `std-microblock/chromatic`) | **None declared upstream** — see below |

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

## chromatic — upstream declares **no license**

Upstream: <https://github.com/std-microblock/chromatic> (no `LICENSE` file, no
license field — GitHub reports `NONE`).

This repository offers a second macOS payload built from chromatic's injectee,
and publishes it as `chromatic-injectee-<tag>-macos-<arch>.dylib`. **Please read
this section before using or redistributing that asset.**

### What we are doing, plainly

* The code is taken from [`muyunya/chromatic`](https://github.com/muyunya/chromatic),
  a **fork** of the upstream project. GitHub's terms permit forking public
  repositories, and the fork relationship keeps the origin visible.
* **We claim no rights over chromatic.** It remains the work of its authors
  (std-microblock and contributors). Nothing in this repository's MIT license
  applies to it, and no authorship is claimed anywhere.
* The payload is built from source in CI, so the corresponding source is public
  and matches the published binary. The two changes the payload needs (a
  reserved `__DATA,__fripack` section, and a teardown fix that stops the host
  from aborting on exit) are visible as commits in that fork.
* **If you are the author and you object to this, open an issue and the asset
  and the build job will be removed.** Same if you would rather it stay but
  under specific terms — a `LICENSE` file upstream is a one-line change and
  everything here becomes unambiguous.

### Why this is still not the same as being licensed

Attribution and a license are different things. Without a license, the default
is "all rights reserved", so downstream users of this asset do not receive a
grant from the chromatic authors — they receive the code under the terms above
and nothing more. If that matters to you, use the Frida-based payload instead:
it is GPL-3.0, which is an explicit grant.

Upstream has been inactive since 2026-03-31, which is why asking directly may not
be practical. That is the reason this is handled as a provenance declaration
rather than as a request for permission.

## GitHub Actions runners

The CI uses the standard GitHub-hosted macOS runners. No third-party actions
beyond `actions/*` are used, so there is nothing else to attribute.
