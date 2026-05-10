#!/usr/bin/env bash
# Builds libs/openssl standalone with Configure + make.
# Config: configs/openssl-build.env
# Output: $BUILD_DIR/install/lib/libssl.*, $BUILD_DIR/install/bin/openssl
# Usage: scripts/build_openssl.sh [--clean] [--jobs N]
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/util.sh"

config_file="$REPO_ROOT/configs/openssl-build.env"

# Defaults
BUILD_DIR=~/build/openssl-ja4-standalone
JOBS=""

clean=0

usage() {
  cat <<'USAGE'
Usage: scripts/build_openssl.sh [--clean] [--jobs N]

Builds libs/openssl standalone using Configure + make.
Config can be overridden in configs/openssl-build.env.

Options:
  --clean       Remove BUILD_DIR before building
  --jobs N      Parallel jobs (default: nproc)
  -h, --help    Show this help
USAGE
}

# Load config file if present
load_env_config "$config_file"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)  clean=1; shift ;;
    --jobs)   JOBS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[error] unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$JOBS" ]]; then
  JOBS=$(detect_jobs)
fi

BUILD_DIR="${BUILD_DIR/#\~/$HOME}"
OPENSSL_SRC="$REPO_ROOT/libs/openssl"

echo "[info] OpenSSL source:  $OPENSSL_SRC"
echo "[info] Build dir:       $BUILD_DIR"
echo "[info] Jobs:            $JOBS"

if [[ ! -d "$OPENSSL_SRC" ]]; then
  echo "[info] libs/openssl not found; initializing managed OpenSSL source"
  "$REPO_ROOT/scripts/apply_patches.sh" --only openssl
fi

if ! git -C "$OPENSSL_SRC" rev-parse --git-dir &>/dev/null; then
  echo "[error] OpenSSL source checkout is not usable: $OPENSSL_SRC" >&2
  exit 1
fi

# Check prerequisites
for tool in perl make; do
  if ! command -v "$tool" &>/dev/null; then
    echo "[error] '$tool' not found — install it first" >&2
    exit 1
  fi
done

if [[ $clean -eq 1 ]] && [[ -d "$BUILD_DIR" ]]; then
  echo "[info] cleaning $BUILD_DIR..."
  rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"

echo "[info] Configuring OpenSSL..."
cd "$OPENSSL_SRC"

./Configure --prefix="$BUILD_DIR/install" --openssldir="$BUILD_DIR/install/ssl"

echo "[info] Building OpenSSL..."
make -j"$JOBS"

echo "[info] Installing OpenSSL..."
make install_sw

echo "[info] OpenSSL build complete."
echo "[info] Libraries: $BUILD_DIR/install/lib/libssl.*, $BUILD_DIR/install/lib/libcrypto.*"
echo "[info] Binary:    $BUILD_DIR/install/bin/openssl"
