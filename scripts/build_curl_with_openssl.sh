#!/usr/bin/env bash
# Builds curl standalone against the patched OpenSSL install.
# Config: configs/curl-build.env
# Output: $BUILD_DIR/install/bin/curl
# Usage: scripts/build_curl_with_openssl.sh [--clean] [--jobs N]
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/util.sh"

config_file="$REPO_ROOT/configs/curl-build.env"
openssl_config_file="$REPO_ROOT/configs/openssl-build.env"

BUILD_DIR=~/build/curl-openssl-ja4
CURL_VERSION=8.19.0
JOBS=""
clean=0

usage() {
  cat <<'USAGE'
Usage: scripts/build_curl_with_openssl.sh [--clean] [--jobs N]

Builds curl against the patched OpenSSL install created by
scripts/build_openssl.sh.

Options:
  --clean       Remove BUILD_DIR before building
  --jobs N      Parallel jobs (default: nproc)
  -h, --help    Show this help
USAGE
}

load_env_config "$config_file"

OPENSSL_BUILD_DIR=~/build/openssl-ja4-standalone
if [[ -f "$openssl_config_file" ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      BUILD_DIR)
        OPENSSL_BUILD_DIR="${value%%#*}"
        OPENSSL_BUILD_DIR="${OPENSSL_BUILD_DIR%"${OPENSSL_BUILD_DIR##*[![:space:]]}"}"
        OPENSSL_BUILD_DIR="${OPENSSL_BUILD_DIR#"${OPENSSL_BUILD_DIR%%[![:space:]]*}"}"
        ;;
    esac
  done < <(grep -v '^\s*#' "$openssl_config_file" | grep '=')
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) clean=1; shift ;;
    --jobs) JOBS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[error] unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$JOBS" ]]; then
  JOBS=$(detect_jobs)
fi

BUILD_DIR="${BUILD_DIR/#\~/$HOME}"
OPENSSL_BUILD_DIR="${OPENSSL_BUILD_DIR/#\~/$HOME}"
OPENSSL_INSTALL_DIR="$OPENSSL_BUILD_DIR/install"
SOURCE_DIR="$BUILD_DIR/source"
TARBALL="$BUILD_DIR/curl-${CURL_VERSION}.tar.gz"
URL="https://curl.se/download/curl-${CURL_VERSION}.tar.gz"

echo "[info] curl version:     $CURL_VERSION"
echo "[info] Build dir:        $BUILD_DIR"
echo "[info] Jobs:             $JOBS"
echo "[info] OpenSSL install:  $OPENSSL_INSTALL_DIR"

if [[ ! -x "$OPENSSL_INSTALL_DIR/bin/openssl" ]]; then
  echo "[info] patched OpenSSL build not found; building OpenSSL first"
  "$REPO_ROOT/scripts/build_openssl.sh" --jobs "$JOBS"
fi

for tool in curl tar make cc; do
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

if [[ ! -f "$TARBALL" ]]; then
  echo "[info] downloading curl source tarball..."
  curl -fL "$URL" -o "$TARBALL"
fi

rm -rf "$SOURCE_DIR"
mkdir -p "$SOURCE_DIR"
echo "[info] extracting curl source..."
tar -xzf "$TARBALL" -C "$SOURCE_DIR" --strip-components=1

cd "$SOURCE_DIR"

# OpenSSL Configure lands in lib/ or lib64/ depending on host distro; pick the
# real path so dependent pkg-config / linker flags do not point at a missing
# directory.
if ! OPENSSL_LIBDIR="$(resolve_install_libdir "$OPENSSL_INSTALL_DIR")"; then
  echo "[error] OpenSSL build not found at $OPENSSL_INSTALL_DIR (looked for lib/ and lib64/) — run scripts/build_openssl.sh first" >&2
  exit 1
fi
export PKG_CONFIG_PATH="$OPENSSL_LIBDIR/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CPPFLAGS="-I$OPENSSL_INSTALL_DIR/include${CPPFLAGS:+ $CPPFLAGS}"
export LDFLAGS="-L$OPENSSL_LIBDIR${LDFLAGS:+ $LDFLAGS}"

echo "[info] configuring curl..."
./configure \
  --prefix="$BUILD_DIR/install" \
  --with-openssl="$OPENSSL_INSTALL_DIR" \
  --without-libpsl \
  --disable-ldap \
  --enable-ipv6

echo "[info] building curl..."
make -j"$JOBS"

echo "[info] installing curl..."
make install

echo "[info] curl build complete."
echo "[info] Binary: $BUILD_DIR/install/bin/curl"
