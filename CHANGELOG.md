# Changelog

All notable changes to JA4 Spoofer are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.2] — 2026-05-13

### Fixed

- Linux launcher icon now renders crisply across the desktop. The previous
  `.deb` shipped a single 2048×2048 PNG inside `hicolor/256x256/apps/`,
  which most desktops (GNOME, Cinnamon, KDE) treat as broken and either
  scale poorly or fall back to the generic application icon. The packager
  now generates one matching PNG per hicolor size (16/32/48/64/128/256/512)
  from `assets/icon.png`.
- The `.desktop` entry sets `StartupWMClass=com.example.ja4_spoofer`
  matching the GApplication application‑id, so the running window in the
  dock / Alt‑Tab finally picks up the JA4 launcher icon instead of the
  default placeholder.
- New `DEBIAN/postinst` + `postrm` hooks refresh `gtk-update-icon-cache`
  and `update-desktop-database` on install/upgrade/remove — without them
  the new icons would only appear after a manual cache rebuild or relogin.

## [1.3.1] — 2026-05-13

### Fixed

- `scripts/run_curl_with_ja4.sh` and `scripts/build_curl_with_openssl.sh`
  no longer hardcode `install/lib/`. OpenSSL's Configure installs to
  `lib64/` on Debian/Ubuntu x86_64, which made the installed `.deb`
  report a misleading "OpenSSL build not found" error even when the
  build had succeeded. A new `resolve_install_libdir` helper in
  `scripts/lib/util.sh` resolves whichever layout is present, and
  `compat_prober.dart` does the same lookup. `scripts/build_openssl.sh`
  additionally pins `--libdir=lib` so future builds are deterministic.
- Linux window/taskbar icon now matches `assets/icon.png`. The
  `flutter_launcher_icons` package is a no-op for Linux, so
  `linux/runner/resources/app_icon.png` previously drifted from the
  canonical source. A new `tools/ja4-spoofer/scripts/sync_app_icon.py`
  regenerates the runner icon, and `package_linux_deb.sh` runs it
  before each build.

### Documentation

- `docs/add-new-tool.md` documents the lib/lib64 pitfall and shows
  contributors how to link new OpenSSL-backed CLI clients via
  `resolve_install_libdir`. Clarifies that Chromium and Firefox link
  their patched TLS stacks (BoringSSL / NSS) statically and are not
  affected.

## [1.3.0] — 2026-05-12

### Added

- `AppShell._initControllers` now uses a re-entry guard so rapid Settings
  saves no longer race two concurrent init passes against the same
  controllers.
- Init failures and background load failures surface as destructive
  `ShadSonner` toasts instead of being swallowed by `unawaited(...)`.
- `Ja4CaptureController` reacts to `SettingsScope` changes via
  `didChangeDependencies`, so an IANA-source toggle hot-reloads the
  registry without leaving the capture page.

### Changed

- `analysis_options.yaml` promotes `unawaited_futures` and
  `discarded_futures` to errors. All ~20 violations were either awaited
  or explicitly wrapped in `unawaited(...)`.

## [1.2.0] — 2026-05-12

### Added

- Release pipeline pins the Flutter SDK via
  `tools/ja4-spoofer/.flutter-version` and caches `$HOME/flutter` plus
  `~/.pub-cache` across runs.
- Each release artifact ships with a `SHA256SUMS` file. The workflow also
  signs `.deb` + `SHA256SUMS` with GPG when `GPG_PRIVATE_KEY` /
  `GPG_PASSPHRASE` repo secrets are configured.
- Release notes are generated from the git log via
  `ncipollo/release-action`'s `generateReleaseNotes`.

### Changed

- The pubspec bump and tag push now happen *after* a successful build, so
  a failed build no longer leaves an orphan tag pointing at broken code.
- `package_linux_deb.sh` strips newlines and surrounding whitespace from
  the pubspec description before embedding it in `DEBIAN/control` to
  keep the field on a single line.

## [1.1.0] — 2026-05-12

### Fixed

- `scripts/lib/util.sh` — `load_env_config` no longer evaluates command
  substitution from config files. A line like `FOO=$(rm -rf ~)` is now
  treated as literal text (and rejected). The new parser keeps the only
  expansion that was actually used (`~/` → `$HOME/`).
- `scripts/apply_patches.sh` — re-running with unique commits on
  `my-changes` no longer silently destroys WIP. The script now aborts
  unless `--force` is passed.
- `scripts/build_firefox_with_patched_nss.sh` — `git clean -fd` is gated
  to ja4-managed checkouts via a `.ja4-managed-checkout` marker, so a
  stray `--workdir` pointing at a developer's own gecko-dev cannot wipe
  their tree.
- `AppLauncherController.smartLaunch` serializes apps sharing the same
  `submoduleName` via a per-submodule mutex, preventing concurrent
  patch runs from corrupting `libs/<sub>`.

## [1.0.0] — 2026-05-12

Initial public release.

- Patch workflows for BoringSSL, NSS, and OpenSSL.
- Flutter desktop GUI (`tools/ja4-spoofer/`) for profile editing, capture,
  randomization, and one-click launch.
- Bundled-runtime model — packaged installs extract scripts/configs/
  patches to `~/.ja4-spoofer/runtime/<version>/` on first launch, no
  repo checkout needed.
- GitHub Actions release pipeline that builds a `.deb` against
  `debian:bullseye-slim` for glibc 2.31 compatibility.
- Seed profiles for Safari, Brave, Tor, Zen, Apple Mail, curl, Chromium,
  Firefox.

[1.3.0]: https://github.com/nurkert/ja4-spoofer/releases/tag/v1.3.0
[1.2.0]: https://github.com/nurkert/ja4-spoofer/releases/tag/v1.2.0
[1.1.0]: https://github.com/nurkert/ja4-spoofer/releases/tag/v1.1.0
[1.0.0]: https://github.com/nurkert/ja4-spoofer/releases/tag/v1.0.0
