#!/usr/bin/env bash
# Builds libs/boringssl standalone with cmake+ninja.
# Config: configs/boringssl-build.env
# Output: $BUILD_DIR/libssl.a, $BUILD_DIR/libcrypto.a, $BUILD_DIR/bssl
# Usage: scripts/build_boringssl.sh [--debug] [--clean] [--jobs N]
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/util.sh"

config_file="$REPO_ROOT/configs/boringssl-build.env"

# Defaults
BUILD_TYPE=Release
BUILD_DIR=~/build/boringssl-ja4-standalone
JOBS=""

debug=0
clean=0

usage() {
  cat <<'USAGE'
Usage: scripts/build_boringssl.sh [--debug] [--clean] [--jobs N]

Builds libs/boringssl standalone using cmake + ninja (without Chromium).
Config can be overridden in configs/boringssl-build.env.

Options:
  --debug       Build type Debug instead of Release
  --clean       Remove BUILD_DIR before building
  --jobs N      Parallel jobs (default: nproc)
  -h, --help    Show this help
USAGE
}

# Load config file if present
load_env_config "$config_file"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)  debug=1; shift ;;
    --clean)  clean=1; shift ;;
    --jobs)   JOBS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[error] unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ $debug -eq 1 ]]; then BUILD_TYPE=Debug; fi

if [[ -z "$JOBS" ]]; then
  JOBS=$(detect_jobs)
fi

BUILD_DIR="${BUILD_DIR/#\~/$HOME}"
BORINGSSL_SRC="$REPO_ROOT/libs/boringssl"

echo "[info] BoringSSL source: $BORINGSSL_SRC"
echo "[info] Build dir:        $BUILD_DIR"
echo "[info] Build type:       $BUILD_TYPE"
echo "[info] Jobs:             $JOBS"

if [[ ! -d "$BORINGSSL_SRC" ]]; then
  echo "[info] libs/boringssl not found; initializing managed BoringSSL source"
  "$REPO_ROOT/scripts/apply_patches.sh" --only boringssl
fi

if ! git -C "$BORINGSSL_SRC" rev-parse --git-dir &>/dev/null; then
  echo "[error] BoringSSL source checkout is not usable: $BORINGSSL_SRC" >&2
  exit 1
fi

# Check prerequisites
for tool in cmake ninja; do
  if ! command -v "$tool" &>/dev/null; then
    echo "[error] '$tool' not found — install it first (e.g. brew install $tool)" >&2
    exit 1
  fi
done

if [[ $clean -eq 1 ]] && [[ -d "$BUILD_DIR" ]]; then
  echo "[info] cleaning $BUILD_DIR..."
  rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"

echo "[info] Configuring BoringSSL..."
cmake -GNinja \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -S "$BORINGSSL_SRC" \
  -B "$BUILD_DIR"

echo "[info] Building BoringSSL..."
ninja -C "$BUILD_DIR" -j"$JOBS"

echo "[info] BoringSSL build complete."
echo "[info] Libraries: $BUILD_DIR/libssl.a, $BUILD_DIR/libcrypto.a"
echo "[info] Binary:    $BUILD_DIR/bssl"
