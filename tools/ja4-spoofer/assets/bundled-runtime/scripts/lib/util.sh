#!/usr/bin/env bash
# Shared utility functions.

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_valid_bool() {
  local v
  v="$(lower "$1")"
  case "$v" in
    1|0|true|false|on|off|yes|no) return 0 ;;
    *) return 1 ;;
  esac
}

detect_jobs() {
  nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4
}

load_env_config() {
  local file="$1"
  if [[ -f "$file" ]]; then
    # shellcheck source=/dev/null
    source <(grep -v '^\s*#' "$file" | grep '=')
  fi
}

# Remove stale git lock files left by crashed processes.
# Usage: cleanup_git_locks <repo-dir>
cleanup_git_locks() {
  local repo_dir="$1"
  local lock
  for lock in "$repo_dir/.git/index.lock" \
              "$repo_dir/.git/shallow.lock" \
              "$repo_dir/.git/refs/heads.lock" \
              "$repo_dir/.git/HEAD.lock"; do
    if [[ -f "$lock" ]]; then
      echo "[warn] removing stale lock: $lock"
      rm -f "$lock"
    fi
  done
}

# Retry a command up to N times with a delay between attempts.
# Usage: retry <max-attempts> <delay-secs> <command...>
retry() {
  local max_attempts="$1" delay="$2"
  shift 2
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [[ "$attempt" -ge "$max_attempts" ]]; then
      echo "[error] command failed after $max_attempts attempts: $*" >&2
      return 1
    fi
    echo "[warn] attempt $attempt/$max_attempts failed, retrying in ${delay}s..."
    sleep "$delay"
    ((attempt++))
  done
}
