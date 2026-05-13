#!/usr/bin/env bash
#
# Builds the Flutter Linux app and packages it as a .deb installer.
#
# Output: dist/ja4-spoofer_<version>-<build>_<arch>.deb
#
# Installs to /opt/ja4-spoofer/ with a launcher symlink in /usr/bin/ja4-spoofer
# and a desktop entry in /usr/share/applications/.
#
# Requires:
#   - flutter (with linux desktop support enabled)
#   - dpkg-deb (Debian/Ubuntu/derivates)
#
# Usage:
#   scripts/package_linux_deb.sh [--no-build] [--no-sync] [--arch <amd64|arm64>] [--version X.Y.Z] [--build-number N]
#
#   --no-build   Skip `flutter build linux --release` and reuse the existing
#                build artifact.
#   --no-sync    Skip the bundled-runtime asset sync from repo root.
#   --arch       Override architecture string in the .deb filename and control
#                file. Defaults to the host's `dpkg --print-architecture`.
#   --version    Override the pubspec version for the .deb metadata.
#   --build-number
#                Debian package revision. Defaults to pubspec build metadata
#                (the number after '+') or 1.

set -euo pipefail

APP_NAME="ja4-spoofer"
APP_BIN_NAME="ja4_spoofer"   # Flutter exposes the Dart package name as the binary
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_OUT="${PROJECT_ROOT}/build/linux"
DIST_DIR="${PROJECT_ROOT}/dist"

cd "${PROJECT_ROOT}"

PUBSPEC_VERSION=$(awk '/^version:/ {print $2}' pubspec.yaml)
VERSION="${PUBSPEC_VERSION%%+*}"
BUILD_NUMBER="${PUBSPEC_VERSION#*+}"
if [[ "${BUILD_NUMBER}" == "${PUBSPEC_VERSION}" ]]; then
  BUILD_NUMBER="1"
fi
DESCRIPTION=$(awk '/^description:/ {sub(/^description:[[:space:]]*"?/, ""); sub(/"?[[:space:]]*$/, ""); print}' pubspec.yaml)
# Sanitize for the .deb control file: it requires a single-line synopsis on
# `Description:` and disallows raw newlines / leading whitespace. Strip
# anything that would corrupt the format.
DESCRIPTION=$(printf '%s' "$DESCRIPTION" | tr -d '\r' | tr '\n\t' '  ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')

NO_BUILD=0
NO_SYNC=0
ARCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)
      NO_BUILD=1
      shift
      ;;
    --no-sync)
      NO_SYNC=1
      shift
      ;;
    --arch)
      ARCH="${2:-}"
      if [[ -z "${ARCH}" ]]; then
        echo "[error] --arch requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      if [[ -z "${VERSION}" ]]; then
        echo "[error] --version requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="${2:-}"
      if [[ -z "${BUILD_NUMBER}" ]]; then
        echo "[error] --build-number requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      sed -n '1,/^set -euo pipefail/p' "$SCRIPT_PATH" | sed -n '/^#/p'
      exit 0
      ;;
    *)
      echo "[error] unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! "${VERSION}" =~ ^[0-9]+(\.[0-9]+){1,2}([~+:.a-zA-Z0-9-]*)?$ ]]; then
  echo "[error] invalid package version: ${VERSION}" >&2
  exit 1
fi
if [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo "[error] build number must be numeric: ${BUILD_NUMBER}" >&2
  exit 1
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "[warn] this script is meant to run on Linux. Cross-packaging from macOS"
  echo "[warn] requires a Linux Flutter SDK + dpkg-deb in PATH."
fi

# Resolve architecture
if [[ -z "${ARCH}" ]]; then
  if command -v dpkg >/dev/null 2>&1; then
    ARCH=$(dpkg --print-architecture)
  else
    case "$(uname -m)" in
      x86_64|amd64) ARCH=amd64 ;;
      aarch64|arm64) ARCH=arm64 ;;
      *) echo "[error] cannot detect arch; pass --arch <amd64|arm64>" >&2; exit 1 ;;
    esac
  fi
fi

# Find Flutter Linux build subdirectory (it varies by arch).
FLUTTER_LINUX_OUT="${BUILD_OUT}/${ARCH}/release/bundle"
case "${ARCH}" in
  amd64) FLUTTER_LINUX_OUT="${BUILD_OUT}/x64/release/bundle" ;;
  arm64) FLUTTER_LINUX_OUT="${BUILD_OUT}/arm64/release/bundle" ;;
esac

DEB_VERSION="${VERSION}-${BUILD_NUMBER}"

if [[ "${NO_SYNC}" -eq 0 ]]; then
  bash "$(dirname "${SCRIPT_PATH}")/sync_bundled_runtime.sh"
  # Keep the Linux runner window icon in lock-step with assets/icon.png.
  # flutter_launcher_icons does not regenerate it for Linux, so without this
  # call the bundled window icon drifts whenever the asset is updated.
  if command -v python3 >/dev/null 2>&1; then
    # Don't fail packaging if Pillow is missing on this builder — only warn.
    # The icon will simply remain whatever is committed under
    # linux/runner/resources/app_icon.png.
    if ! python3 "$(dirname "${SCRIPT_PATH}")/sync_app_icon.py"; then
      echo "[warn] app icon sync failed — window icon may be stale" >&2
    fi
  else
    echo "[warn] python3 not found — skipping app icon sync (window icon may be stale)"
  fi
else
  echo "[info] --no-sync set; using existing assets/bundled-runtime/ and runner icons"
fi

if [[ "${NO_BUILD}" -eq 0 ]]; then
  echo "[info] flutter build linux --release ..."
  flutter build linux --release --dart-define=BUNDLE_VERSION="${DEB_VERSION}"
else
  echo "[info] --no-build set; using existing artifacts in ${FLUTTER_LINUX_OUT}"
fi

if [[ ! -d "${FLUTTER_LINUX_OUT}" ]]; then
  echo "[error] flutter build output not found: ${FLUTTER_LINUX_OUT}" >&2
  echo "[hint]  ensure linux desktop is enabled: flutter config --enable-linux-desktop" >&2
  exit 1
fi

if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "[error] dpkg-deb is required (Debian/Ubuntu)." >&2
  echo "[hint]  apt install dpkg-dev" >&2
  exit 1
fi

mkdir -p "${DIST_DIR}"

DEB_NAME="${APP_NAME}_${DEB_VERSION}_${ARCH}"
STAGE_DIR=$(mktemp -d -t ja4-deb-XXXXXX)
trap 'rm -rf "${STAGE_DIR}"' EXIT

PKG_ROOT="${STAGE_DIR}/${DEB_NAME}"

# --- Filesystem layout inside the .deb ---
mkdir -p "${PKG_ROOT}/DEBIAN"
mkdir -p "${PKG_ROOT}/opt/${APP_NAME}"
mkdir -p "${PKG_ROOT}/usr/bin"
mkdir -p "${PKG_ROOT}/usr/share/applications"
mkdir -p "${PKG_ROOT}/usr/share/icons/hicolor/256x256/apps"

# --- Copy the built app ---
echo "[info] staging app payload"
cp -r "${FLUTTER_LINUX_OUT}"/* "${PKG_ROOT}/opt/${APP_NAME}/"

# --- Launcher in /usr/bin ---
cat > "${PKG_ROOT}/usr/bin/${APP_NAME}" <<EOF
#!/bin/sh
exec /opt/${APP_NAME}/${APP_BIN_NAME} "\$@"
EOF
chmod 755 "${PKG_ROOT}/usr/bin/${APP_NAME}"

# --- Desktop entry ---
cat > "${PKG_ROOT}/usr/share/applications/${APP_NAME}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=JA4 Spoofer
Comment=${DESCRIPTION}
Exec=/usr/bin/${APP_NAME}
Icon=${APP_NAME}
Terminal=false
Categories=Network;Security;Development;
EOF

# --- Optional icon (256x256 png) ---
if [[ -f "${PROJECT_ROOT}/assets/icon-256.png" ]]; then
  cp "${PROJECT_ROOT}/assets/icon-256.png" \
     "${PKG_ROOT}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
elif [[ -f "${PROJECT_ROOT}/assets/icon.png" ]]; then
  cp "${PROJECT_ROOT}/assets/icon.png" \
     "${PKG_ROOT}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
elif [[ -f "${PROJECT_ROOT}/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png" ]]; then
  # Fall back to scaled-down macOS icon if a dedicated linux icon doesn't exist
  cp "${PROJECT_ROOT}/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png" \
     "${PKG_ROOT}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
fi

# --- DEBIAN control file ---
INSTALLED_SIZE=$(du -sk "${PKG_ROOT}" | awk '{print $1}')

cat > "${PKG_ROOT}/DEBIAN/control" <<EOF
Package: ${APP_NAME}
Version: ${DEB_VERSION}
Section: net
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0, libglib2.0-0, libstdc++6, libgcc-s1
Maintainer: JA4 Spoofer Maintainers <nurkert@users.noreply.github.com>
Homepage: https://github.com/nurkert/ja4-spoofer
Description: ${DESCRIPTION}
 Desktop GUI for controlled TLS ClientHello and JA4 fingerprint experiments.
 The installed app extracts its scripts, configs and patches to
 ~/.ja4-spoofer/runtime/<version>/, so normal users do not need a repository
 checkout just to build or launch the managed targets.
EOF

# --- Permissions ---
find "${PKG_ROOT}" -type d -exec chmod 0755 {} +
find "${PKG_ROOT}/opt" -type f -name "${APP_BIN_NAME}" -exec chmod 0755 {} +

# --- Build the .deb ---
echo "[info] dpkg-deb --build ${PKG_ROOT}"
dpkg-deb --build "${PKG_ROOT}" >/dev/null

DEB_FILE="${DIST_DIR}/${DEB_NAME}.deb"
mv "${STAGE_DIR}/${DEB_NAME}.deb" "${DEB_FILE}"

DEB_BYTES=$(stat --format=%s "${DEB_FILE}" 2>/dev/null || stat -f %z "${DEB_FILE}")
DEB_HUMAN=$(awk -v b="${DEB_BYTES}" 'BEGIN{printf "%.1f MiB", b/1048576}')

echo ""
echo "[ok] ${DEB_FILE}"
echo "[ok] size: ${DEB_HUMAN}"
echo "[ok] install with: sudo dpkg -i \"${DEB_FILE}\""
echo "[ok] uninstall with: sudo apt remove ${APP_NAME}"
