#!/usr/bin/env bash
# Shared environment setup: PATH augmentation, REPO_ROOT, OS detection, Bash version check.

# GUI launchers don't source ~/.zshrc — add common tool paths if missing.
for _dir in "/opt/homebrew/bin" "/usr/local/bin" "$HOME/.cargo/bin"; do
  [[ -d "$_dir" && ":$PATH:" != *":$_dir:"* ]] && export PATH="$_dir:$PATH"
done

# Repo root (relative to the sourcing script, not this file).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"

# OS detection
IS_MACOS=0; [[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=1

# Bash version check (>= 4 needed for mapfile, associative arrays, etc.)
# If running under old macOS system bash, re-exec the calling script with
# Homebrew bash. $0 is the top-level script (e.g. run_browser.sh).
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for _candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    # shellcheck disable=SC2016
    # Single quotes are intentional: BASH_VERSINFO must expand in the
    # candidate bash, not in this (possibly outdated) shell.
    if [[ -x "$_candidate" ]] && "$_candidate" -c '[[ ${BASH_VERSINFO[0]} -ge 4 ]]' 2>/dev/null; then
      exec "$_candidate" "$0" "$@"
    fi
  done
  echo "[error] bash >= 4 required (found $BASH_VERSION)" >&2
  echo "[hint]  brew install bash" >&2
  exit 1
fi
