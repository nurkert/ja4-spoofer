#!/usr/bin/env bash
# Builds Chromium with patched BoringSSL (replaces Chromium's third-party BoringSSL).
# Config: configs/chromium-build-pin.env
# Usage: scripts/build_chromium_with_patched_boringssl.sh [--check-only] [--jobs N]
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/util.sh"

# depot_tools must be in PATH (not covered by lib/env.sh)
for _dir in "$HOME/depot_tools"; do
  [[ -d "$_dir" && ":$PATH:" != *":$_dir:"* ]] && export PATH="$_dir:$PATH"
done

config_file="$REPO_ROOT/configs/chromium-build-pin.env"

# Defaults
CHROMIUM_BRANCH=main
CHROMIUM_REF=""
BORINGSSL_REPLACEMENT_SRC="libs/boringssl"
JOBS=""

check_only=0

usage() {
  cat <<'USAGE'
Usage: scripts/build_chromium_with_patched_boringssl.sh [--check-only] [--jobs N]

Fetches/updates Chromium source, symlinks libs/boringssl as Chromium's third-party
BoringSSL, then builds chrome via gn + autoninja.
Config can be overridden in configs/chromium-build-pin.env.

Options:
  --check-only  Only check prerequisites; do not build
  --jobs N      Parallel jobs passed to autoninja (default: system default)
  -h, --help    Show this help
USAGE
}

# Load config file if present
load_env_config "$config_file"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) check_only=1; shift ;;
    --jobs)       JOBS="$2"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "[error] unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# --- Prerequisite checks ---
echo "[info] Checking prerequisites..."

for tool in python3 git; do
  if ! command -v "$tool" &>/dev/null; then
    echo "[error] '$tool' not found" >&2
    exit 1
  fi
done

if ! command -v gclient &>/dev/null; then
  echo "[error] depot_tools not found — add depot_tools to PATH" >&2
  echo "[hint] https://chromium.googlesource.com/chromium/tools/depot_tools" >&2
  exit 1
fi

if ! command -v gn &>/dev/null; then
  echo "[error] 'gn' not found — install via depot_tools or system package" >&2
  exit 1
fi

if ! command -v autoninja &>/dev/null && ! command -v ninja &>/dev/null; then
  echo "[error] 'autoninja' or 'ninja' not found" >&2
  exit 1
fi

NINJA_CMD=$(command -v autoninja 2>/dev/null || command -v ninja)

if [[ $check_only -eq 1 ]]; then
  echo "[info] All prerequisites satisfied."
  exit 0
fi

# --- Chromium source ---
CHROMIUM_SRC="${CHROMIUM_SRC:-$HOME/chromium/src}"
CHROMIUM_PARENT="$(dirname "$CHROMIUM_SRC")"

if [[ -d "$CHROMIUM_SRC/.git" ]]; then
  # Full checkout present — update to the desired ref.
  echo "[info] Updating Chromium..."
  cleanup_git_locks "$CHROMIUM_SRC"
  cd "$CHROMIUM_SRC"
  retry 3 5 git fetch origin
  git checkout "${CHROMIUM_REF:-origin/$CHROMIUM_BRANCH}"

  # Detect whether DEPS were never synced: after `fetch --nohooks` the DEPS
  # directories exist as empty placeholders.  `gclient sync` without --force
  # treats them as already-synced and silently skips them.  Probe a few key
  # DEPS to decide whether a forced sync is needed.
  _force_flag=""
  for _probe in third_party/angle third_party/boringssl/src tools/clang; do
    if [[ -d "$CHROMIUM_SRC/$_probe" && -z "$(ls -A "$CHROMIUM_SRC/$_probe" 2>/dev/null)" ]]; then
      echo "[info] DEPS appear unsynced (empty dirs found) — using --force"
      _force_flag="--force"
      break
    fi
  done

  cd "$CHROMIUM_PARENT"
  gclient sync $_force_flag --with_branch_heads --with_tags
elif [[ -f "$CHROMIUM_PARENT/.gclient" ]]; then
  # .gclient exists but src/ is missing or incomplete — a previous fetch was
  # interrupted. Resume with gclient sync instead of re-running fetch.
  echo "[info] Resuming interrupted Chromium checkout (gclient sync)..."
  cd "$CHROMIUM_PARENT"
  gclient sync --force --nohooks --with_branch_heads --with_tags
  cd "$CHROMIUM_SRC"
  gclient runhooks
else
  # No checkout at all — fresh fetch.
  echo "[info] Fetching Chromium (this takes a long time)..."
  mkdir -p "$CHROMIUM_PARENT"
  cd "$CHROMIUM_PARENT"
  fetch --nohooks chromium
  cd "$CHROMIUM_SRC"
  gclient runhooks
fi

# --- Symlink patched BoringSSL ---
BORINGSSL_SRC_ABS="$(cd "$REPO_ROOT/$BORINGSSL_REPLACEMENT_SRC" 2>/dev/null || echo "$BORINGSSL_REPLACEMENT_SRC" && pwd)"
if [[ -n "$BORINGSSL_REPLACEMENT_SRC" ]]; then
  if [[ "$BORINGSSL_REPLACEMENT_SRC" = /* ]]; then
    BORINGSSL_SRC_ABS="$BORINGSSL_REPLACEMENT_SRC"
  else
    if [[ ! -d "$REPO_ROOT/$BORINGSSL_REPLACEMENT_SRC" ]]; then
      echo "[info] patched BoringSSL source missing; initializing managed source"
      "$REPO_ROOT/scripts/apply_patches.sh" --only boringssl
    fi
    BORINGSSL_SRC_ABS="$(cd "$REPO_ROOT" && cd "$BORINGSSL_REPLACEMENT_SRC" && pwd)"
  fi

  BORINGSSL_DEST="$CHROMIUM_SRC/third_party/boringssl/src"
  echo "[info] Symlinking $BORINGSSL_SRC_ABS -> $BORINGSSL_DEST"

  if [[ -d "$BORINGSSL_DEST" && ! -L "$BORINGSSL_DEST" ]]; then
    mv "$BORINGSSL_DEST" "${BORINGSSL_DEST}.chromium-orig"
  fi
  rm -f "$BORINGSSL_DEST"
  ln -sf "$BORINGSSL_SRC_ABS" "$BORINGSSL_DEST"
fi

# --- GN configure ---
OUT_DIR="$CHROMIUM_SRC/out/ja4-stable"
echo "[info] Configuring Chromium build..."
cd "$CHROMIUM_SRC"

if [[ ! -f "$OUT_DIR/args.gn" ]]; then
  gn gen "$OUT_DIR" --args='is_debug=false symbol_level=0 enable_nacl=false'
fi

# --- Build ---
echo "[info] Building Chromium (this takes a very long time)..."
NINJA_ARGS=()
if [[ -n "$JOBS" ]]; then
  NINJA_ARGS+=(-j "$JOBS")
fi
"$NINJA_CMD" -C "$OUT_DIR" "${NINJA_ARGS[@]}" chrome

echo "[info] Chromium build complete."
echo "[info] Binary: $OUT_DIR/Chromium.app (macOS) or $OUT_DIR/chrome (Linux)"
