#!/usr/bin/env bash
#
# Sync repository-root scripts/, configs/ and patches/ into the Flutter
# app's assets/bundled-runtime/ folder so the packaged installer can
# extract them to ~/.ja4-spoofer/runtime/<version>/ on first launch.
#
# Idempotent: safe to run repeatedly. Uses rsync --delete to remove stale
# files that no longer exist upstream.
#
# Usage:
#   tools/ja4-spoofer/scripts/sync_bundled_runtime.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"           # tools/ja4-spoofer/
REPO_ROOT="$(cd "${APP_ROOT}/../.." && pwd)"          # repository root
DEST="${APP_ROOT}/assets/bundled-runtime"

if ! command -v rsync >/dev/null 2>&1; then
  echo "[error] rsync is required" >&2
  exit 1
fi

for src in scripts configs patches; do
  if [[ ! -d "${REPO_ROOT}/${src}" ]]; then
    echo "[error] missing source directory: ${REPO_ROOT}/${src}" >&2
    exit 1
  fi
done

echo "[info] syncing bundled-runtime assets"
echo "       from ${REPO_ROOT}"
echo "       to   ${DEST}"

mkdir -p "${DEST}/scripts" "${DEST}/configs"

# scripts/ — mirror everything including subdirs (lib/, browsers/)
rsync -a --delete \
  --exclude='__pycache__' --exclude='*.pyc' \
  "${REPO_ROOT}/scripts/" "${DEST}/scripts/"

# configs/ — flat directory, mirror directly
rsync -a --delete "${REPO_ROOT}/configs/" "${DEST}/configs/"

# patches/ — only patch and BASE_REF files, no compiled artefacts
for lib in boringssl nss openssl; do
  mkdir -p "${DEST}/patches/${lib}"
  rsync -a --delete \
    --include='*.patch' --include='BASE_REF' --exclude='*' \
    "${REPO_ROOT}/patches/${lib}/" "${DEST}/patches/${lib}/"
done

echo "[ok] bundled-runtime assets in sync"
