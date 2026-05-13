# Scripts

Index of the shell + Python utilities under `scripts/`. The Flutter GUI
invokes the launchers and build scripts directly; the verify and refresh
scripts are typically run from the command line during development.

## Patch management

| Script | Purpose |
|---|---|
| `apply_patches.sh` | Reset each submodule under `libs/` to its `BASE_REF` and replay every `patches/<lib>/*.patch` on top. Aborts if `my-changes` carries WIP commits — pass `--force` to override. |
| `refresh_patches.sh` | Re-export the patch set from the current submodule commits. `--include-wip` also writes `.diff` snapshots of uncommitted work. |

## Library builds

| Script | TLS stack | Notes |
|---|---|---|
| `build_boringssl.sh` | BoringSSL | Standalone build of the patched library. |
| `build_nss.sh` | NSS | Standalone NSS build (not part of a browser). |
| `build_openssl.sh` | OpenSSL | Builds the patched OpenSSL into `BUILD_DIR`. |

## Client builds

| Script | Client | Underlying stack |
|---|---|---|
| `build_chromium_with_patched_boringssl.sh` | Chromium | Patches `third_party/boringssl/src` and runs the Chromium build. |
| `build_firefox_with_patched_nss.sh` | Firefox (gecko-dev) | Bootstraps the Mozilla toolchain on first run, patches `security/nss`, and builds. |
| `build_curl_with_openssl.sh` | curl | Builds curl against the patched OpenSSL. |

## Client launchers

| Script | Client | Notes |
|---|---|---|
| `run_chromium_with_ja4.sh` | Chromium | Thin wrapper around `run_browser.sh`. |
| `run_firefox_with_ja4.sh` | Firefox | Same. |
| `run_curl_with_ja4.sh` | curl | CLI runner, supports `--dump`, `--dry-run`. |
| `run_boringssl_with_ja4.sh` | BoringSSL smoke test | For verifying the patched library directly. |
| `run_browser.sh` | shared | Implements the common launch flow; called by the per-browser wrappers. |
| `start_ja4_webui.sh` | helper | Spawns the local Python web UI used for visualising captures. |

Every launcher accepts the flags documented in
[`docs/advanced-launch.md`](../docs/advanced-launch.md).

## Verification

| Script | Purpose |
|---|---|
| `ja4_verify.sh` | Run the verification harness against the fixture profiles in `tests/`. |
| `ja4_verify_all.sh` | Iterate `ja4_verify.sh` across every fixture profile. |

## Helpers / analysis

| Script | Purpose |
|---|---|
| `lib.sh`, `lib/env.sh`, `lib/util.sh`, `lib/parse_ja4_args.sh`, `lib/process.sh` | Sourced by the other scripts. `util.sh` exposes the safe `load_env_config` parser, the `retry` helper, `cleanup_git_locks`, and `resolve_install_libdir` (picks `install/lib` vs `install/lib64` so any OpenSSL‑backed client works regardless of host). |
| `browsers/*.sh` | Per-browser overrides for the shared launcher. |
| `analyze_ja3.py` | Analyse JA3 hashes (older fingerprint format) from captured pcaps. |
| `evaluate_boringssl_ja4.py` | Sweep BoringSSL parameter variations and score the resulting JA4 fingerprint. |
| `evaluate_firefox_nss_ja4.py` | Same idea for NSS / Firefox. |
| `fcs_emit.py` | Emit fingerprint configurations using the Fingerprint Config Standard. |

The two `evaluate_*` scripts are how the random-mutation work in
[`docs/randomizer-research-results.md`](../docs/randomizer-research-results.md) was produced.
