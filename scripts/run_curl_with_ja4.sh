#!/usr/bin/env bash
# Launch a client backed by the patched OpenSSL build with an OpenSSL JA4 config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/util.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/parse_ja4_args.sh"

config_file="$REPO_ROOT/configs/openssl-build.env"
BUILD_DIR=~/build/openssl-ja4-standalone
CURL_BUILD_DIR=~/build/curl-openssl-ja4

load_env_config "$config_file"
BUILD_DIR="${BUILD_DIR/#\~/$HOME}"
CURL_BUILD_DIR="${CURL_BUILD_DIR/#\~/$HOME}"

BROWSER_NAME="OpenSSL"
BROWSER_BIN_OPTION="--binary"
BROWSER_DEFAULT_CONFIG_OUT="/tmp/openssl-ja4-run.conf"
BROWSER_DEFAULT_DUMP_PATH="/tmp/openssl-ja4-effective.conf"
BROWSER_DUMP_ENV_VAR="OPENSSL_JA4_DUMP"

usage() {
  cat <<'USAGE'
Usage: scripts/run_curl_with_ja4.sh [options] [-- <client args>]

Options:
  --config <path>                 Base config file to use/copy
  --config-out <path>             Output config path (default: /tmp/openssl-ja4-run.conf)
  --dump <path>                   Dump output path (default: /tmp/openssl-ja4-effective.conf)
  --no-dump                       Disable OPENSSL_JA4_DUMP
  --openssl                       Use the built openssl CLI for verification
  --binary <path>                 Use a custom client binary linked against patched OpenSSL
  --dry-run                       Print env + command, do not execute
  --show-config                   Print effective config before launch
  --tls-min <ver>                 tls_min
  --tls-max <ver>                 tls_max
  --strict <bool>                 strict (true = no safe exact fallback)
  --cipher-suites <csv>           cipher_suites
  --cipher-mode <reorder|exact>   cipher_mode
  --alpn <csv>                    alpn
  --signature-algorithms <csv>    signature_algorithms
  --extension-order <csv>         extension_order
  --extension-mode <reorder|exact>
  --sni-mode <present|domain|none|ip>
  --enable-grease <bool>          enable_grease
  --set <key=value>               Extra key/value appended last
  -h, --help                      Show this help
USAGE
}

use_openssl=0
remaining_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --openssl)
      use_openssl=1
      shift
      ;;
    --)
      remaining_args+=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      remaining_args+=("$1")
      shift
      ;;
  esac
done

parse_ja4_args "${remaining_args[@]+"${remaining_args[@]}"}"

INSTALL_DIR="$BUILD_DIR/install"
if [[ ! -d "$INSTALL_DIR/lib" ]]; then
  echo "[error] OpenSSL build not found at $INSTALL_DIR — run scripts/build_openssl.sh first" >&2
  exit 1
fi

config_out="${JA4_CONFIG_OUT:-$BROWSER_DEFAULT_CONFIG_OUT}"
write_ja4_config "$config_out" "$JA4_CONFIG_IN" "scripts/run_curl_with_ja4.sh"

if [[ "$JA4_SHOW_CONFIG" -eq 1 ]]; then
  show_ja4_config "$config_out" "OpenSSL JA4"
fi

if [[ $IS_MACOS -eq 1 ]]; then
  export DYLD_LIBRARY_PATH="$INSTALL_DIR/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
else
  export LD_LIBRARY_PATH="$INSTALL_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

export OPENSSL_JA4_CONFIG="$config_out"
if [[ "$JA4_DUMP_ENABLED" -eq 1 ]]; then
  export OPENSSL_JA4_DUMP="${JA4_DUMP_PATH:-$BROWSER_DEFAULT_DUMP_PATH}"
else
  unset OPENSSL_JA4_DUMP || true
fi

if [[ "$use_openssl" -eq 1 ]]; then
  cmd=("$INSTALL_DIR/bin/openssl")
  if [[ ! -x "${cmd[0]}" ]]; then
    echo "[error] openssl binary not found at ${cmd[0]}" >&2
    exit 1
  fi
elif [[ -n "$JA4_BROWSER_BIN" ]]; then
  cmd=("$JA4_BROWSER_BIN")
  if [[ ! -x "${cmd[0]}" ]]; then
    echo "[error] custom client binary not executable: ${cmd[0]}" >&2
    exit 1
  fi
elif [[ -x "$CURL_BUILD_DIR/install/bin/curl" ]]; then
  cmd=("$CURL_BUILD_DIR/install/bin/curl")
else
  cmd=("$INSTALL_DIR/bin/openssl")
fi

if [[ "${#JA4_BROWSER_EXTRA_ARGS[@]}" -gt 0 ]]; then
  cmd+=("${JA4_BROWSER_EXTRA_ARGS[@]}")
fi

if [[ "$JA4_DRY_RUN" -eq 1 ]]; then
  [[ -n "${OPENSSL_JA4_CONFIG:-}" ]] && echo "[dry-run] OPENSSL_JA4_CONFIG=$OPENSSL_JA4_CONFIG"
  [[ -n "${OPENSSL_JA4_DUMP:-}" ]] && echo "[dry-run] OPENSSL_JA4_DUMP=$OPENSSL_JA4_DUMP"
  [[ -n "${DYLD_LIBRARY_PATH:-}" ]] && echo "[dry-run] DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH"
  [[ -n "${LD_LIBRARY_PATH:-}" ]] && echo "[dry-run] LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
  printf '[dry-run] command:'
  printf ' %q' "${cmd[@]}"
  printf '\n'
  exit 0
fi

if [[ "${cmd[0]}" == "$INSTALL_DIR/bin/openssl" ]]; then
  echo "[info] launching patched OpenSSL CLI"
else
  echo "[info] launching client linked against patched OpenSSL: ${cmd[0]}"
fi
echo "[info] OPENSSL_JA4_CONFIG=$OPENSSL_JA4_CONFIG"
if [[ "$JA4_DUMP_ENABLED" -eq 1 ]]; then
  echo "[info] OPENSSL_JA4_DUMP=$OPENSSL_JA4_DUMP"
fi

exec "${cmd[@]}"
