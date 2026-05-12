<p align="center">
  <img src="assets/header.png" alt="JA4 Spoofer" width="100%">
</p>

# JA4 Spoofer

JA4 Spoofer is an open-source toolkit for controlled TLS ClientHello and JA4
fingerprint experiments. It patches common TLS stacks, builds client
applications against those patched stacks, and launches them with explicit
JA4-oriented profiles.

The project currently targets:

| Client | TLS stack | Status |
|---|---|---|
| Chromium / Brave-style builds | BoringSSL | Patched via `patches/boringssl/` |
| Firefox | NSS | Patched via `patches/nss/` |
| curl / OpenSSL CLI paths | OpenSSL | Patched via `patches/openssl/` |

## Features

- Patch workflows for BoringSSL, NSS and OpenSSL.
- A Flutter desktop GUI for profile editing, capture, randomization and launch.
- Scriptable CLI launchers for Firefox, Chromium and curl.
- A shared profile model for JA4-relevant ClientHello fields.
- Seed profiles and fixtures for repeatable verification.
- Diagnostic dumps that compare requested and effective wire values.

## Responsible Use

This project is intended for interoperability testing, measurement, client
fingerprinting research, and defensive analysis. Do not use it to bypass access
controls, impersonate users, evade abuse detection, or violate the terms of
services you do not control.

## Quickstart

Installable Linux releases are published as `.deb` files. After installation,
the GUI extracts its managed scripts, configs and patches to
`~/.ja4-spoofer/runtime/<version>/`; users do not need to point the app at a
repository checkout.

For source development:

```bash
git clone <repo-url>
cd ja4-spoofer
git submodule update --init --recursive

cd tools/ja4-spoofer
flutter pub get
flutter run -d macos   # or -d linux / -d windows
```

In the GUI:

1. Select or create a JA4 profile.
2. Open **Launch**.
3. Click an app action. The first run clones or initializes the required
   upstream source on the host, checks out the pinned base ref, applies the
   patch stack, builds the target and launches it. Later runs launch directly
   while the patch stamp is still fresh.

<p align="center">
  <img src="assets/launcher.png" alt="JA4 Spoofer — Launch tab" width="680">
</p>

| TLS Configurator | Profile Library | JA4 Capture |
|---|---|---|
| <img src="assets/configurator.png" alt="TLS Configurator" width="220"> | <img src="assets/profiles.png" alt="Profile Library" width="220"> | <img src="assets/capture.png" alt="JA4 Capture" width="220"> |

Build times vary heavily. curl/OpenSSL is usually quick, Firefox can take around
an hour on a laptop, and Chromium can take several hours plus significant disk
space.

## Repository Layout

```text
configs/                 pinned build configuration
docs/                    technical documentation
libs/                    upstream TLS/client submodules
patches/                 JA4 patch sets applied to submodules
scripts/                 patch, build, launch and verification scripts
tests/                   JA4 fixtures and expected diagnostics
tools/ja4-spoofer/       Flutter desktop GUI
```

The `libs/` directories are upstream projects checked out as submodules. Local
JA4 changes are stored as patch files under `patches/`; the patched submodule
working trees are build artifacts, not the source of truth.

Packaged GUI builds do not bundle these upstream source trees. They bundle only
the project scripts, configs and patch files. On the user's machine, the build
flow clones the required upstream source fresh into the writable runtime area
and then applies the checked-in patch stack.

## Releases

Linux `.deb` releases are built by `.github/workflows/release.yml`.

- Run the workflow manually with a semantic version such as `1.2.3`.
- The workflow updates `tools/ja4-spoofer/pubspec.yaml`, commits the release
  version, creates tag `v1.2.3`, builds the Flutter Linux app and uploads the
  `.deb` to the GitHub release.
- Tag pushes `v*.*.*` also build a `.deb`, but the tag must match the pubspec
  version.

## Documentation

- [Documentation index](docs/README.md)
- [Managed libraries and patch workflow](docs/managed-libs.md)
- [Advanced launch options](docs/advanced-launch.md)
- [Fingerprint Config Standard](docs/fingerprint-config-standard.md)
- [JA4 capabilities and limits](docs/ja4-spoofing-summary.md)
- [Flutter GUI guide](tools/ja4-spoofer/README.md)

## Common Commands

```bash
# Apply all patch stacks to their pinned submodule refs.
scripts/apply_patches.sh

# Refresh patch files from local submodule commits.
scripts/refresh_patches.sh

# Run the verification harness against fixture profiles.
scripts/ja4_verify.sh

# Run Flutter tests.
cd tools/ja4-spoofer && flutter test
```

## License

The project-owned code, scripts, patches and documentation are released under
the **GNU General Public License v3.0 or later** (`GPL-3.0-or-later`). See
[LICENSE](LICENSE) for the full license text.

Third-party projects under `libs/` keep their own upstream licenses. This
repository license does not relicense OpenSSL, BoringSSL, NSS, Nginx, JA4 or
other external submodules.

<p align="center">
  <img src="tools/ja4-spoofer/assets/icon.png" alt="JA4 Spoofer icon" width="64" height="64">
</p>
