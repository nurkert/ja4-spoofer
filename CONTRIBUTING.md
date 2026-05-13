# Contributing to JA4 Spoofer

Thanks for taking the time to contribute. The project is small and welcomes
focused improvements — bug fixes, new TLS profiles, new client targets,
documentation polish.

## Getting set up

```bash
git clone https://github.com/nurkert/ja4-spoofer
cd ja4-spoofer/tools/ja4-spoofer
flutter pub get
flutter run -d linux       # or -d macos / -d windows
```

Per-app build prerequisites (Chromium, Firefox, curl) are listed inside the
GUI's `Launch` tab.

## Reporting issues

Open a GitHub issue with:

- What you tried (commit SHA + commands)
- What you expected vs what happened
- Relevant log excerpts from the GUI's terminal panel or the script output

For security-sensitive reports, follow [SECURITY.md](SECURITY.md) instead of
filing a public issue.

## Pull requests

Branch off `main`, make focused changes, open a PR. Keep diffs small and
self-contained — easier to review and easier to revert.

Before pushing:

```bash
cd tools/ja4-spoofer
flutter analyze     # zero issues required (lints are strict)
flutter test
```

Shell scripts under `scripts/` should pass `shellcheck` when reasonable.

## Commit messages

- One short imperative subject line (e.g. `harden apply_patches against WIP loss`)
- No Conventional Commit prefixes (`feat:`, `fix:`, `chore:` …)
- No body unless it documents a non-obvious *why*
- No co-author or generated-by trailers

## Releases & CHANGELOG

`CHANGELOG.md` is the source of truth for release notes — the release
workflow extracts the section for the current version and uses it as the
GitHub Release body. Before opening a release PR or pushing a `v*.*.*`
tag, add a new section in [Keep a Changelog][keepachangelog] format:

```markdown
## [X.Y.Z] — YYYY-MM-DD

### Added / Changed / Fixed / Documentation

- …
```

Also append the matching reference link at the bottom of the file:

```markdown
[X.Y.Z]: https://github.com/nurkert/ja4-spoofer/releases/tag/vX.Y.Z
```

If the section is missing the release workflow aborts with a clear error.

[keepachangelog]: https://keepachangelog.com/en/1.1.0/

## Adding a new client target

1. Drop a new YAML in `tools/ja4-spoofer/assets/descriptors/`
2. Add the build script under `scripts/build_<app>_with_patched_<lib>.sh`
3. Add a launch script under `scripts/run_<app>_with_ja4.sh`
4. Verify with `scripts/ja4_verify.sh`

See [docs/add-new-tool.md](docs/add-new-tool.md) for the details.

## Code of conduct

By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
