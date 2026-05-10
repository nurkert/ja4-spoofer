#!/usr/bin/env bash
# Unified JA4 browser launcher.
# Usage: scripts/run_browser.sh --browser <firefox|chromium> [options] [-- <browser args>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/util.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/process.sh"

# --- Extract --browser <name> from args ---
browser_id=""
remaining_args=()
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--browser" ]]; then
    browser_id="$2"
    shift 2
  elif [[ "$1" == "--" ]]; then
    remaining_args+=("$@")
    break
  else
    remaining_args+=("$1")
    shift
  fi
done

if [[ -z "$browser_id" ]]; then
  echo "[error] --browser <name> is required (e.g. --browser firefox)" >&2
  exit 1
fi

browser_def="$SCRIPT_DIR/browsers/${browser_id}.sh"
if [[ ! -f "$browser_def" ]]; then
  echo "[error] unknown browser: $browser_id (no $browser_def found)" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$browser_def"

source "$SCRIPT_DIR/lib/parse_ja4_args.sh"
parse_ja4_args "${remaining_args[@]+"${remaining_args[@]}"}"

# --- Resolve browser binary ---
browser_bin="${JA4_BROWSER_BIN:-}"

if [[ -z "$browser_bin" ]]; then
  browser_bin="${!BROWSER_BIN_ENV_VAR:-}"
fi

if [[ -n "$browser_bin" ]]; then
  if [[ ! -x "$browser_bin" ]]; then
    echo "[error] $BROWSER_NAME binary is not executable: $browser_bin" >&2
    exit 1
  fi
else
  for candidate in "${BROWSER_SEARCH_PATHS[@]}"; do
    if [[ -x "$candidate" ]]; then
      browser_bin="$candidate"
      break
    fi
  done
fi

if [[ -z "$browser_bin" ]]; then
  echo "[error] no $BROWSER_NAME binary found automatically." >&2
  echo "[hint] pass $BROWSER_BIN_OPTION <path> (built binary from $BROWSER_BUILD_HINT)." >&2
  exit 1
fi

# --- Handle existing processes ---
handle_existing_processes "$browser_bin" "$BROWSER_NAME" \
  "$JA4_KILL_EXISTING" "$JA4_ALLOW_EXISTING" "$JA4_DRY_RUN"

# --- Config ---
config_out="${JA4_CONFIG_OUT:-$BROWSER_DEFAULT_CONFIG_OUT}"
write_ja4_config "$config_out" "$JA4_CONFIG_IN" "scripts/run_browser.sh"

if [[ "$JA4_SHOW_CONFIG" -eq 1 ]]; then
  show_ja4_config "$config_out" "$BROWSER_NAME JA4"
fi

# --- Profile dir ---
if [[ -n "$JA4_PROFILE_DIR" ]]; then
  mkdir -p "$JA4_PROFILE_DIR"
fi

# --- Build command ---
declare -a cmd
cmd=("$browser_bin")
cmd+=("${BROWSER_EXTRA_DEFAULT_ARGS[@]+"${BROWSER_EXTRA_DEFAULT_ARGS[@]}"}")

if [[ -n "$JA4_PROFILE_DIR" ]]; then
  if [[ "$BROWSER_PROFILE_FORMAT" == "equals" ]]; then
    cmd+=("${BROWSER_PROFILE_FLAG}=${JA4_PROFILE_DIR}")
  else
    cmd+=("$BROWSER_PROFILE_FLAG" "$JA4_PROFILE_DIR")
  fi
fi

if [[ "${#JA4_BROWSER_EXTRA_ARGS[@]}" -gt 0 ]]; then
  cmd+=("${JA4_BROWSER_EXTRA_ARGS[@]}")
elif [[ -n "$BROWSER_DEFAULT_URL" ]]; then
  cmd+=("$BROWSER_DEFAULT_URL")
fi

# --- Build env array ---
declare -a env_args=()
for env_var in "${BROWSER_CONFIG_ENV_VARS[@]}"; do
  env_args+=("${env_var}=${config_out}")
done

dump_path="${JA4_DUMP_PATH:-$BROWSER_DEFAULT_DUMP_PATH}"
if [[ "$JA4_DUMP_ENABLED" -eq 1 ]]; then
  env_args+=("${BROWSER_DUMP_ENV_VAR}=${dump_path}")
fi

# --- Dry run ---
if [[ "$JA4_DRY_RUN" -eq 1 ]]; then
  for ev in "${env_args[@]}"; do
    echo "[dry-run] $ev"
  done
  if [[ "$JA4_DUMP_ENABLED" -eq 0 ]]; then
    echo "[dry-run] $BROWSER_DUMP_ENV_VAR is disabled"
  fi
  printf '[dry-run] command:'
  printf ' %q' "${cmd[@]}"
  printf '\n'
  exit 0
fi

# --- Launch ---
echo "[info] launching $BROWSER_NAME with JA4 runtime config"
echo "[info] binary: $browser_bin"
for ev in "${env_args[@]}"; do
  echo "[info] $ev"
done

exec env "${env_args[@]}" "${cmd[@]}"
