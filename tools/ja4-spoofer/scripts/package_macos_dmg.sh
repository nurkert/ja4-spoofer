#!/usr/bin/env bash
#
# Builds the Flutter macOS app and packages it into a draggable .dmg installer.
#
# Output: dist/ja4-spoofer-<version>-macos.dmg
#
# When opened in Finder the user sees a window with the app on the left and an
# alias to /Applications on the right — drag-to-install. No external tooling
# required, uses macOS' built-in hdiutil.
#
# Usage:
#   scripts/package_macos_dmg.sh [--no-build] [--no-sync]
#
#   --no-build   Skip `flutter build macos --release` and reuse the existing
#                build artifact. Useful for fast iteration on the packaging
#                step.
#   --no-sync    Skip the bundled-runtime asset sync from repo root.

set -euo pipefail

APP_NAME="ja4-spoofer"
APP_BUNDLE="${APP_NAME}.app"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_OUT="${PROJECT_ROOT}/build/macos/Build/Products/Release"
DIST_DIR="${PROJECT_ROOT}/dist"

cd "${PROJECT_ROOT}"

VERSION=$(awk '/^version:/ {split($2, a, "+"); print a[1]}' pubspec.yaml)
DMG_VOLUME_NAME="JA4 Spoofer ${VERSION}"
DMG_FILE="${DIST_DIR}/${APP_NAME}-${VERSION}-macos.dmg"

NO_BUILD=0
NO_SYNC=0
for arg in "$@"; do
  case "${arg}" in
    --no-build) NO_BUILD=1 ;;
    --no-sync) NO_SYNC=1 ;;
    -h|--help)
      sed -n '1,/^set -euo pipefail/p' "$SCRIPT_PATH" | sed -n '/^#/p'
      exit 0
      ;;
    *)
      echo "[error] unknown arg: ${arg}" >&2
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[error] this script must run on macOS" >&2
  exit 1
fi

if [[ "${NO_SYNC}" -eq 0 ]]; then
  bash "$(dirname "${SCRIPT_PATH}")/sync_bundled_runtime.sh"
else
  echo "[info] --no-sync set; using existing assets/bundled-runtime/"
fi

if [[ "${NO_BUILD}" -eq 0 ]]; then
  echo "[info] flutter build macos --release ..."
  flutter build macos --release --dart-define=BUNDLE_VERSION="${VERSION}"
else
  echo "[info] --no-build set; using existing artifacts in ${BUILD_OUT}"
fi

if [[ ! -d "${BUILD_OUT}/${APP_BUNDLE}" ]]; then
  echo "[error] build artifact not found: ${BUILD_OUT}/${APP_BUNDLE}" >&2
  echo "[hint]  re-run without --no-build to build it" >&2
  exit 1
fi

mkdir -p "${DIST_DIR}"

# Stage the dmg contents in a temp dir so the layout is deterministic.
STAGE_DIR=$(mktemp -d -t ja4-dmg-stage)
trap 'rm -rf "${STAGE_DIR}"' EXIT

echo "[info] staging dmg contents in ${STAGE_DIR}"
cp -R "${BUILD_OUT}/${APP_BUNDLE}" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"

# Optional: README on the volume so the user sees a one-liner before install.
cat > "${STAGE_DIR}/README.txt" <<EOF
JA4 Spoofer ${VERSION}
=====================

Drag ${APP_BUNDLE} onto the Applications folder symlink to install.

On first launch the app extracts its scripts, configs and patches to
~/.ja4-spoofer/runtime/${VERSION}/. Patched apps are built separately under
the configured build directories.

Repo: https://github.com/nurkert/ja4-spoofer
EOF

echo "[info] removing previous dmg if present"
rm -f "${DMG_FILE}"

echo "[info] creating dmg ${DMG_FILE}"
hdiutil create \
  -volname "${DMG_VOLUME_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_FILE}" >/dev/null

# Verify the dmg is mountable.
echo "[info] verifying dmg ..."
hdiutil verify "${DMG_FILE}" >/dev/null

DMG_BYTES=$(stat -f '%z' "${DMG_FILE}")
DMG_HUMAN=$(awk -v b="${DMG_BYTES}" 'BEGIN{printf "%.1f MiB", b/1048576}')

echo ""
echo "[ok] ${DMG_FILE}"
echo "[ok] size: ${DMG_HUMAN}"
echo "[ok] open with: open \"${DMG_FILE}\""
