#!/usr/bin/env bash
# Shared JA4 argument parser.
# Requires BROWSER_NAME, BROWSER_BIN_OPTION, BROWSER_DEFAULT_CONFIG_OUT,
# BROWSER_DEFAULT_DUMP_PATH, BROWSER_DUMP_ENV_VAR set before sourcing.

JA4_CONFIG_IN=""
JA4_CONFIG_OUT=""
JA4_DUMP_PATH="${BROWSER_DEFAULT_DUMP_PATH:-}"
JA4_DUMP_ENABLED=1
JA4_PROFILE_DIR=""
JA4_TLS_MIN=""
JA4_TLS_MAX=""
JA4_STRICT=""
JA4_CIPHER_SUITES=""
JA4_CIPHER_MODE=""
JA4_ALPN=""
JA4_SIGNATURE_ALGORITHMS=""
JA4_SUPPORTED_VERSIONS=""
JA4_SUPPORTED_GROUPS=""
JA4_KEY_SHARE_GROUPS=""
JA4_PSK_KEY_EXCHANGE_MODES=""
JA4_EXTENSION_ORDER=""
JA4_EXTENSION_MODE=""
JA4_SNI_MODE=""
JA4_ENABLE_GREASE=""
JA4_ENABLE_CH_XTN_PERMUTATION=""
declare -a JA4_EXTRA_KV=()
JA4_SHOW_CONFIG=0
JA4_ALLOW_EXISTING=0
JA4_KILL_EXISTING=0
JA4_DRY_RUN=0
JA4_BROWSER_BIN=""
declare -a JA4_BROWSER_EXTRA_ARGS=()

usage() {
  local browser_lower="${BROWSER_NAME,,}"
  cat <<USAGE
Usage: scripts/run_${browser_lower}_with_ja4.sh [options] [-- <${browser_lower} args>]

Generate/apply JA4 runtime config and launch patched $BROWSER_NAME.

Options:
  ${BROWSER_BIN_OPTION} <path>    $BROWSER_NAME binary path (auto-detect if omitted)
  --browser-bin <path>            Browser binary path (alias)
  --config <path>                 Base config file to use/copy
  --config-out <path>             Output config path (default: $BROWSER_DEFAULT_CONFIG_OUT)
  --dump <path>                   Write effective config snapshot (default: $BROWSER_DEFAULT_DUMP_PATH)
  --no-dump                       Do not set $BROWSER_DUMP_ENV_VAR
  --profile-dir <path>            Profile/user-data dir
  --tls-min <ver>                 tls_min (e.g. 1.2, 1.3, 771, 772)
  --tls-max <ver>                 tls_max
  --strict <bool>                 strict (1/0,true/false,on/off,yes/no)
  --cipher-suites <csv>           cipher_suites (ordered)
  --cipher-mode <reorder|exact>   cipher_mode
  --alpn <csv>                    alpn (ordered)
  --signature-algorithms <csv>    signature_algorithms (ordered)
  --supported-versions <csv>      supported_versions (ordered)
  --supported-groups <csv>        supported_groups (ordered)
  --key-share-groups <csv>        key_share_groups (ordered)
  --psk-key-exchange-modes <csv>  psk_key_exchange_modes (ordered)
  --extension-order <csv>         extension_order (ordered)
  --extension-mode <reorder|exact>
  --sni-mode <present|domain|none|ip>
  --enable-grease <bool>          enable_grease (1/0,true/false,on/off,yes/no)
  --enable-ch-xtn-permutation <bool>
                                  enable_ch_xtn_permutation (same bool set)
  --set <key=value>               Extra key/value (repeatable, appended last)
  --show-config                   Print effective config before launch
  --allow-existing                Allow launch while same binary is already running
  --kill-existing                 Kill already running processes first
  --dry-run                       Print env + command, do not launch
  -h, --help                      Show this help
USAGE
}

parse_ja4_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      $BROWSER_BIN_OPTION|--browser-bin)
        JA4_BROWSER_BIN="$2"; shift 2 ;;
      --config)
        JA4_CONFIG_IN="$2"; shift 2 ;;
      --config-out)
        JA4_CONFIG_OUT="$2"; shift 2 ;;
      --dump)
        JA4_DUMP_PATH="$2"; JA4_DUMP_ENABLED=1; shift 2 ;;
      --no-dump)
        JA4_DUMP_ENABLED=0; shift ;;
      --profile-dir)
        JA4_PROFILE_DIR="$2"; shift 2 ;;
      --tls-min)
        JA4_TLS_MIN="$2"; shift 2 ;;
      --tls-max)
        JA4_TLS_MAX="$2"; shift 2 ;;
      --strict)
        JA4_STRICT="$2"; shift 2 ;;
      --cipher-suites)
        JA4_CIPHER_SUITES="$2"; shift 2 ;;
      --cipher-mode)
        JA4_CIPHER_MODE="$2"; shift 2 ;;
      --alpn)
        JA4_ALPN="$2"; shift 2 ;;
      --signature-algorithms|--signature-schemes)
        JA4_SIGNATURE_ALGORITHMS="$2"; shift 2 ;;
      --supported-versions)
        JA4_SUPPORTED_VERSIONS="$2"; shift 2 ;;
      --supported-groups)
        JA4_SUPPORTED_GROUPS="$2"; shift 2 ;;
      --key-share-groups)
        JA4_KEY_SHARE_GROUPS="$2"; shift 2 ;;
      --psk-key-exchange-modes)
        JA4_PSK_KEY_EXCHANGE_MODES="$2"; shift 2 ;;
      --extension-order|--extensions)
        JA4_EXTENSION_ORDER="$2"; shift 2 ;;
      --extension-mode)
        JA4_EXTENSION_MODE="$2"; shift 2 ;;
      --sni-mode)
        JA4_SNI_MODE="$2"; shift 2 ;;
      --enable-grease)
        JA4_ENABLE_GREASE="$2"; shift 2 ;;
      --enable-ch-xtn-permutation)
        JA4_ENABLE_CH_XTN_PERMUTATION="$2"; shift 2 ;;
      --set)
        JA4_EXTRA_KV+=("$2"); shift 2 ;;
      --show-config)
        JA4_SHOW_CONFIG=1; shift ;;
      --allow-existing)
        JA4_ALLOW_EXISTING=1; shift ;;
      --kill-existing)
        JA4_KILL_EXISTING=1; shift ;;
      --dry-run)
        JA4_DRY_RUN=1; shift ;;
      -h|--help)
        usage; exit 0 ;;
      --)
        shift; JA4_BROWSER_EXTRA_ARGS=("$@"); break ;;
      *)
        echo "[error] unknown option: $1" >&2
        usage >&2
        exit 1 ;;
    esac
  done

  if [[ "$JA4_ALLOW_EXISTING" -eq 1 && "$JA4_KILL_EXISTING" -eq 1 ]]; then
    echo "[error] use either --allow-existing or --kill-existing, not both" >&2
    exit 1
  fi

  if [[ -n "$JA4_CONFIG_IN" && ! -f "$JA4_CONFIG_IN" ]]; then
    echo "[error] --config file not found: $JA4_CONFIG_IN" >&2
    exit 1
  fi

  validate_ja4_params
}
