# JA4 Spoofer — Flutter Desktop GUI

Desktop GUI for controlled JA4 fingerprint experiments with Chromium, Brave-style builds, Firefox and curl. It patches the underlying SSL libraries (BoringSSL, NSS, OpenSSL), builds the apps, and launches them with a configured JA4 profile.

## Quickstart

For normal Linux users, install the `.deb` from GitHub Releases and start
`ja4-spoofer`. The app extracts its scripts, configs and patches to
`~/.ja4-spoofer/runtime/<version>/` automatically; no repository path needs to
be configured in Settings.

For source development:

```bash
git clone <repo> && cd <repo>
git submodule update --init --recursive
cd tools/ja4-spoofer
flutter pub get
flutter run -d macos      # or -d linux / -d windows
```

In the GUI:

1. Pick a profile in **TLS Configurator** (or capture one via **JA4 Capture**, or pick a saved one from **Profile Library**).
2. Go to **Launch**, find the app you want, click the action button.
3. The button is dynamic — it reads "Patch, Build & Launch" the first time and walks the full chain automatically. After a successful build it shrinks to just "Launch".

That's it. No `scripts/*.sh` invocation needed for normal use.

## Auto-Chain

`smartLaunch` in `app_launcher_controller.dart` handles the full pipeline per app:

1. **Patch** — runs `scripts/apply_patches.sh --only <submodule>`. Resets the SSL-lib submodule to its base ref and re-applies every `patches/<sub>/*.patch` on top.
2. **Build** — runs the app's build script (`scripts/build_<app>_with_patched_<lib>.sh`). In packaged installs, missing upstream source trees are cloned fresh into `~/.ja4-spoofer/runtime/<version>/libs/*` before patching. On macOS, Mozilla apps auto-run `mach bootstrap` once to install the bundled clang + SDK in `~/.mozbuild/`.
3. **Launch** — runs the app's launch script with the active JA4 profile passed as flags.

### Stale-binary detection

After every successful build the controller writes a SHA256 stamp to `~/.ja4-spoofer/stamps/<app>.stamp` covering:

- All `patches/<sub>/*.patch` files
- The build script itself

On the next click, the stamp is recomputed and compared. **Mismatch ⇒ full re-patch + rebuild before launch.** Match ⇒ binary is fresh, just launch.

This means a `git pull` that touches patches, lying logic, build flags, toolchain selection or SDK paths automatically invalidates cached binaries. Users never have to clean by hand.

### Concurrency

`smartLaunchInProgress` blocks re-entry so double-clicking the action button can't interleave a second patch/build over an in-flight one.

## Supported Apps

| App         | SSL lib     | Build script                                |
|-------------|-------------|---------------------------------------------|
| Chromium    | BoringSSL   | `build_chromium_with_patched_boringssl.sh`  |
| Brave       | BoringSSL   | (Chromium build pipeline)                   |
| Firefox     | NSS         | `build_firefox_with_patched_nss.sh`         |
| curl        | OpenSSL     | `build_curl_with_openssl.sh`                |

App descriptors live in `assets/descriptors/*.yaml` — adding a new browser/CLI is a YAML file plus a launch script.

## System requirements

To run the GUI itself:
- **Flutter 3.x** (any recent stable channel)
- **Git** with submodule support

Per-app build prerequisites are listed inside the GUI: in the **Launch** tab, every tile has a small ⓘ next to its status — click it to see the exact list of tools, version constraints and install hints for that app. The same data lives in `assets/descriptors/*.yaml` under each `build.requirements:` block.

High-level summary:

| App                  | Needs                                                                        |
|----------------------|------------------------------------------------------------------------------|
| Firefox              | Xcode CLT, `bash >= 4`, `python <= 3.12`, `mercurial`, `git`. `mach bootstrap` is auto-run on first build and pulls clang + Rust + SDK into `~/.mozbuild/`. |
| Chromium / Brave     | Xcode CLT, `depot_tools` on `$PATH`, `cmake`, `bash >= 4`, `python <= 3.12`, `git`. `gn` and `ninja` come with depot_tools. |
| curl (OpenSSL)       | `cc`, `make`, `perl`, `tar`, `curl`, `git` — all standard CLT/`build-essential` packages. |

Disk: ~80 GB for the full Chromium tree, ~25 GB for Firefox, <2 GB for curl/OpenSSL.

First-time Firefox build is 60–90 min on Apple Silicon; first Chromium is several hours; curl is <2 min. Subsequent rebuilds are incremental and fast unless patches or build scripts change.

## Local data

- `~/.ja4-spoofer/profiles/`  — saved JA4 profiles (JSON)
- `~/.ja4-spoofer/profiles/.seeded` — marker that the bundled seed profiles have been copied (delete to re-seed)
- `~/.ja4-spoofer/apps/`      — discovered/cached app descriptors
- `~/.ja4-spoofer/runtime/`   — extracted packaged runtime plus cloned upstream sources for installed builds
- `~/.ja4-spoofer/stamps/`    — patch-stamps for stale-binary detection
- `~/.ja4-spoofer/settings.json` — optional source checkout path and privacy/network preferences

### Seed profiles

On first launch the GUI copies a set of pre-captured profiles (Safari, Brave, Zen, Tor, Apple Mail, curl, Chromium, Firefox) from `assets/seed-profiles/` into `~/.ja4-spoofer/profiles/`. Edit or delete them freely — they won't be re-seeded unless you remove the `.seeded` marker file.

## Architecture

```text
lib/
  app/                            # ShadApp wiring, theme, top-level shell
  core/
    models/                       # AppDescriptor, FingerprintProfile, ...
    services/                     # PatchService, ScriptLauncherService, AppDescriptorService
    utils/                        # profile_args, compatibility_checker
  features/
    app_launcher/                 # smartLaunch + auto-chain (the heart)
    quick_launch/                 # Launch tab UI
    tls_configurator/             # JA4 profile editor
    profile_library/              # saved-profile browser
    ja4_capture/                  # passive sniff to build a profile
    settings/                     # optional source checkout + preferences
```

## Tests

```bash
flutter test
```

Captured profiles force `enable_grease=0` and `enable_ch_xtn_permutation=0` for deterministic replay. The related tests should pass and protect that behavior.

## Packaging — installable artifacts

Two packaging scripts produce ready-to-distribute installers in `dist/`:

### macOS — drag-to-install `.dmg`

```bash
scripts/package_macos_dmg.sh
# → dist/ja4-spoofer-1.0.0-macos.dmg
```

Builds the Flutter macOS app (`flutter build macos --release`), stages it next to an `Applications`-symlink, and packs it into a compressed UDZO disk image with `hdiutil`. Double-click the `.dmg` and drag the app onto the Applications symlink — that's the install.

Flag `--no-build` reuses the existing `build/macos/Build/Products/Release/ja4-spoofer.app` if you only want to re-package without recompiling.

Requirements: macOS, Xcode CLT, Flutter with macOS desktop enabled. No external dependencies — uses macOS' built-in `hdiutil`.

### Linux — Debian `.deb`

```bash
scripts/package_linux_deb.sh
# → dist/ja4-spoofer_1.0.0-1_amd64.deb
```

Builds the Flutter Linux app, lays it out in the standard Debian filesystem hierarchy (`/opt/ja4-spoofer/`, launcher symlink in `/usr/bin/`, desktop entry in `/usr/share/applications/`, icon in `/usr/share/icons/`) and produces a `.deb` via `dpkg-deb --build`.

Install:

```bash
sudo dpkg -i dist/ja4-spoofer_1.0.0-1_amd64.deb
sudo apt -f install     # resolves any missing deps
```

Uninstall via `sudo apt remove ja4-spoofer`. Architecture (`amd64` / `arm64`) is auto-detected via `dpkg --print-architecture`; override with `--arch <arch>`. Flag `--no-build` reuses the existing `build/linux/<arch>/release/bundle/`.

Requirements: Linux host with `flutter` (linux desktop enabled via `flutter config --enable-linux-desktop`) and `dpkg-deb` (Debian/Ubuntu/derivates: `apt install dpkg-dev`).

### GitHub Releases

`.github/workflows/release.yml` builds Linux `.deb` artifacts automatically.
Run it manually with version `X.Y.Z`; it updates `pubspec.yaml`, commits
`chore: release vX.Y.Z`, creates tag `vX.Y.Z`, builds the package and uploads
it to the GitHub release.

### Notes

- Both scripts read the version from `pubspec.yaml`; the Linux script also
  accepts `--version` and `--build-number` for CI.
- The `dist/` directory is git-ignored.
- The patched SSL libraries (`libs/{boringssl,nss,openssl}`) and the host apps (Chromium, Firefox, curl) are **not bundled** in either installer. The installed GUI bundles scripts/configs/patches only; the in-app "Patch, Build & Launch" flow clones upstream sources on the host, checks out the pinned base refs, applies patches and builds local binaries.
