#!/usr/bin/env bash
# Launch the standalone BoringSSL bssl client with BORINGSSL_JA4_* runtime config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/util.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/parse_ja4_args.sh"

config_file="$REPO_ROOT/configs/boringssl-build.env"
BUILD_DIR=~/build/boringssl-ja4-standalone

load_env_config "$config_file"
BUILD_DIR="${BUILD_DIR/#\~/$HOME}"

BROWSER_NAME="boringssl"
BROWSER_BIN_OPTION="--binary"
BROWSER_DEFAULT_CONFIG_OUT="/tmp/boringssl-ja4-run.conf"
BROWSER_DEFAULT_DUMP_PATH="/tmp/boringssl-ja4-effective.conf"
BROWSER_DUMP_ENV_VAR="BORINGSSL_JA4_DUMP"

connect="example.com:443"
server_name=""
http_path="/raw"
http_wait_seconds="0.35"
no_http_request=0
remaining_args=()

usage() {
  cat <<'USAGE'
Usage: scripts/run_boringssl_with_ja4.sh [options] [-- <bssl args>]

Launches the standalone BoringSSL bssl client with JA4 runtime configuration.

BoringSSL helper options:
  --connect <host:port>           Target for default bssl client mode
                                  (default: example.com:443)
  --server-name <name>            SNI/Host for default mode (default: derived from --connect)
  --http-path <path>              HTTP path sent in default mode (default: /raw)
  --http-wait <seconds>           Wait after sending request (default: 0.35)
  --no-http-request               Do not auto-send HTTP request in default mode

JA4 options:
  --config <path>                 Base config file to copy/extend
  --config-out <path>             Output config path
  --dump <path>                   BORINGSSL_JA4_DUMP output path
  --no-dump                       Disable BORINGSSL_JA4_DUMP
  --tls-min <ver>
  --tls-max <ver>
  --strict <bool>
  --cipher-suites <csv>
  --cipher-mode <reorder|exact>
  --alpn <csv>
  --signature-algorithms <csv>
  --supported-versions <csv>
  --supported-groups <csv>
  --key-share-groups <csv>
  --psk-key-exchange-modes <csv>
  --extension-order <csv>
  --extension-mode <reorder|exact>
  --sni-mode <present|domain|none|ip>
  --enable-grease <bool>
  --enable-ch-xtn-permutation <bool>
  --set <key=value>
  --show-config
  --dry-run
  --binary <path>                 Custom bssl binary path

Pass custom bssl args:
  Use '--' to pass raw bssl arguments, e.g.
    scripts/run_boringssl_with_ja4.sh -- --help
    scripts/run_boringssl_with_ja4.sh -- --version
USAGE
}

derive_server_name() {
  local addr="$1"
  if [[ "$addr" == \[*\]:* ]]; then
    addr="${addr#\[}"
    addr="${addr%%]*}"
    printf '%s' "$addr"
    return
  fi
  if [[ "$addr" == *:* ]]; then
    addr="${addr%:*}"
  fi
  printf '%s' "$addr"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --connect)
      connect="$2"
      shift 2
      ;;
    --server-name)
      server_name="$2"
      shift 2
      ;;
    --http-path)
      http_path="$2"
      shift 2
      ;;
    --http-wait)
      http_wait_seconds="$2"
      shift 2
      ;;
    --no-http-request)
      no_http_request=1
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

if ! [[ "$http_wait_seconds" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "[error] --http-wait must be a number, got: $http_wait_seconds" >&2
  exit 1
fi

parse_ja4_args "${remaining_args[@]+"${remaining_args[@]}"}"

config_out="${JA4_CONFIG_OUT:-$BROWSER_DEFAULT_CONFIG_OUT}"
write_ja4_config "$config_out" "$JA4_CONFIG_IN" "scripts/run_boringssl_with_ja4.sh"

if [[ "$JA4_SHOW_CONFIG" -eq 1 ]]; then
  show_ja4_config "$config_out" "BoringSSL JA4"
fi

bssl_bin=""
if [[ -n "$JA4_BROWSER_BIN" ]]; then
  bssl_bin="$JA4_BROWSER_BIN"
elif [[ -x "$BUILD_DIR/bssl" ]]; then
  bssl_bin="$BUILD_DIR/bssl"
elif [[ -x "$BUILD_DIR/tool/bssl" ]]; then
  # Backward-compatible fallback for older local layouts.
  bssl_bin="$BUILD_DIR/tool/bssl"
fi

if [[ -z "$bssl_bin" || ! -x "$bssl_bin" ]]; then
  echo "[error] bssl binary not found or not executable." >&2
  echo "[hint] build first: scripts/build_boringssl.sh" >&2
  echo "[hint] or pass --binary <path>" >&2
  exit 1
fi

if [[ -z "$server_name" ]]; then
  server_name="$(derive_server_name "$connect")"
fi

export BORINGSSL_JA4_CONFIG="$config_out"
if [[ "$JA4_DUMP_ENABLED" -eq 1 ]]; then
  export BORINGSSL_JA4_DUMP="${JA4_DUMP_PATH:-$BROWSER_DEFAULT_DUMP_PATH}"
else
  unset BORINGSSL_JA4_DUMP || true
fi

declare -a cmd=()
if [[ "${#JA4_BROWSER_EXTRA_ARGS[@]}" -gt 0 ]]; then
  cmd=("$bssl_bin" "${JA4_BROWSER_EXTRA_ARGS[@]}")
else
  cmd=(
    "$bssl_bin"
    client
    -connect "$connect"
    -server-name "$server_name"
  )
fi

if [[ "$JA4_DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] BORINGSSL_JA4_CONFIG=$BORINGSSL_JA4_CONFIG"
  if [[ "$JA4_DUMP_ENABLED" -eq 1 ]]; then
    echo "[dry-run] BORINGSSL_JA4_DUMP=$BORINGSSL_JA4_DUMP"
  else
    echo "[dry-run] BORINGSSL_JA4_DUMP is disabled"
  fi
  printf '[dry-run] command:'
  printf ' %q' "${cmd[@]}"
  printf '\n'
  if [[ "$no_http_request" -eq 0 && "${#JA4_BROWSER_EXTRA_ARGS[@]}" -eq 0 ]]; then
    echo "[dry-run] auto HTTP request: GET $http_path (Host: $server_name), wait ${http_wait_seconds}s"
  fi
  exit 0
fi

echo "[info] launching standalone BoringSSL client: $bssl_bin"
echo "[info] BORINGSSL_JA4_CONFIG=$BORINGSSL_JA4_CONFIG"
if [[ "$JA4_DUMP_ENABLED" -eq 1 ]]; then
  echo "[info] BORINGSSL_JA4_DUMP=$BORINGSSL_JA4_DUMP"
fi

if [[ "$no_http_request" -eq 0 && "${#JA4_BROWSER_EXTRA_ARGS[@]}" -eq 0 ]]; then
  echo "[info] auto-request: GET $http_path (Host: $server_name)"
  echo "[info] waiting ${http_wait_seconds}s before closing stdin"
  {
    printf 'GET %s HTTP/1.0\r\n' "$http_path"
    printf 'Host: %s\r\n' "$server_name"
    printf 'Connection: close\r\n'
    printf '\r\n'
    sleep "$http_wait_seconds"
  } | "${cmd[@]}"
  exit $?
fi

exec "${cmd[@]}"
