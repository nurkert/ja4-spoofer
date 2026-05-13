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

# Read a KEY=VALUE config file and export the keys.
#
# Treats values as literal strings — does NOT evaluate command substitution,
# parameter expansion, backticks, or process substitution. The only allowed
# transformation is a leading `~/` expanded to `$HOME/`. Values containing
# shell metacharacters ($ ` ; | & < > ( ) { } ! " ') are rejected so a
# tampered config file cannot inject commands when later consumed by the
# caller.
#
# Keys must match `^[A-Z_][A-Z0-9_]*$`. Lines starting with `#` and inline
# trailing comments (whitespace + #) are stripped.
load_env_config() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    # Skip blank lines and full-line comments
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    # Require KEY=VALUE format
    [[ "$line" != *=* ]] && continue

    key="${line%%=*}"
    value="${line#*=}"

    # Reject keys that don't match the safe pattern
    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue

    # Strip inline comments preceded by whitespace (` # ...` or `\t# ...`)
    if [[ "$value" =~ ^(.*[^[:space:]])[[:space:]]+#.*$ ]]; then
      value="${BASH_REMATCH[1]}"
    elif [[ "$value" =~ ^[[:space:]]*#.*$ ]]; then
      value=""
    fi

    # Trim surrounding whitespace
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    # Strip a single layer of surrounding double or single quotes
    if [[ ${#value} -ge 2 && "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ ${#value} -ge 2 && "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi

    # Expand a leading `~/` to `$HOME/` (the only expansion we allow).
    # Use substring slicing rather than pattern stripping so bash's own
    # tilde expansion in `${var#~/}` patterns can't corrupt the result.
    # Tilde is intentionally compared as a literal below — we are inspecting
    # raw config text, not shell-expanding it.
    # shellcheck disable=SC2088
    if [[ "$value" == "~" ]]; then
      value="$HOME"
    elif [[ "${value:0:2}" == "~/" ]]; then
      value="$HOME/${value:2}"
    fi

    # Reject any remaining shell metacharacters that would matter if the
    # consuming script ever uses `eval` or unquoted expansion.
    local unsafe_re='[$`;|&<>(){}!"'"'"']'
    if [[ "$value" =~ $unsafe_re ]]; then
      echo "[error] $file: rejecting unsafe value for $key" >&2
      return 1
    fi

    printf -v "$key" '%s' "$value"
    # shellcheck disable=SC2163
    # $key holds the variable name (e.g. FOO), so `export "$key"` exports
    # the variable named FOO. That is the desired indirect export.
    export "$key"
  done < "$file"
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

# Resolve the actual library directory of an `install/` prefix.
#
# OpenSSL Configure picks `lib/` or `lib64/` depending on the host (Debian on
# x86_64 defaults to lib64, macOS/Arch use lib). Callers should not hardcode
# either — pass them through this helper so run/build scripts work regardless
# of how Configure landed.
#
# Echoes the resolved absolute path on stdout, or returns 1 if neither exists.
resolve_install_libdir() {
  local install_dir="$1"
  for candidate in lib lib64; do
    if [[ -d "$install_dir/$candidate" ]]; then
      printf '%s\n' "$install_dir/$candidate"
      return 0
    fi
  done
  return 1
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
