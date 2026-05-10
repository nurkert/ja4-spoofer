#!/usr/bin/env bash
# Builds the patched NSS inside the pinned Firefox/gecko tree.
# This is the same supported build path the GUI already uses for the full Firefox build,
# but limited to the NSS subtree so the "Build NSS" action stays reliable.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/util.sh"

debug=0
clean=0
jobs=""
python_bin=""
rust_toolchain=""

usage() {
  cat <<'USAGE'
Usage: scripts/build_nss.sh [--debug] [--clean] [--jobs N] [--python PATH] [--rust-toolchain NAME]

Builds the patched NSS inside the pinned Firefox/gecko source tree.

Options:
  --debug                  Accepted for compatibility; Gecko NSS builds use the existing mozconfig.
  --clean                  Remove the Firefox objdir before rebuilding NSS.
  --jobs N                 Build parallelism (default: auto-detect)
  --python PATH            Python interpreter for mach (e.g. /opt/homebrew/bin/python3.12)
  --rust-toolchain NAME    rustup toolchain/version to use for mach (e.g. 1.83.0)
  -h, --help               Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      debug=1
      shift
      ;;
    --clean)
      clean=1
      shift
      ;;
    --jobs)
      jobs="$2"
      shift 2
      ;;
    --python)
      python_bin="$2"
      shift 2
      ;;
    --rust-toolchain)
      rust_toolchain="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[error] unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$jobs" ]]; then
  jobs="$(detect_jobs)"
fi

workdir="${HOME}/build/firefox-ja4-stable"
src_dir="$workdir/gecko-dev"
obj_dir="$src_dir/obj-ja4-stable"

if [[ ! -d "$src_dir/.git" ]]; then
  echo "[error] Firefox source tree not found at $src_dir" >&2
  echo "[hint] run scripts/build_firefox_with_patched_nss.sh once first" >&2
  exit 1
fi

if [[ "$debug" -eq 1 ]]; then
  echo "[warn] --debug is accepted for compatibility, but NSS is built through Gecko's configured objdir."
fi

if [[ "$clean" -eq 1 && -d "$obj_dir" ]]; then
  echo "[info] cleaning Firefox objdir before NSS-only build: $obj_dir"
  rm -rf "$obj_dir"
fi

cmd=(scripts/build_firefox_with_patched_nss.sh --nss-only --jobs "$jobs")
if [[ -n "$python_bin" ]]; then
  cmd+=(--python "$python_bin")
fi
if [[ -n "$rust_toolchain" ]]; then
  cmd+=(--rust-toolchain "$rust_toolchain")
fi

echo "[info] delegating to Gecko NSS-only build path"
"${cmd[@]}"
