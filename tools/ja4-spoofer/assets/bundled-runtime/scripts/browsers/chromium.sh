# Browser declaration: Chromium with patched BoringSSL

BROWSER_NAME="Chromium"
BROWSER_BIN_ENV_VAR="CHROMIUM_BIN"
BROWSER_BIN_OPTION="--chromium-bin"
BROWSER_SEARCH_PATHS=(
  "$HOME/chromium/src/out/ja4-stable/Chromium.app/Contents/MacOS/Chromium"
  "$HOME/chromium/src/out/ja4-stable/chrome"
  "/Applications/Chromium.app/Contents/MacOS/Chromium"
)
BROWSER_CONFIG_ENV_VARS=("BORINGSSL_JA4_CONFIG")
BROWSER_DUMP_ENV_VAR="BORINGSSL_JA4_DUMP"
BROWSER_DEFAULT_CONFIG_OUT="/tmp/boringssl-ja4-run.conf"
BROWSER_DEFAULT_DUMP_PATH="/tmp/boringssl-ja4-effective.conf"
BROWSER_PROFILE_FLAG="--user-data-dir"
BROWSER_PROFILE_FORMAT="equals"
# --no-sandbox is required for the local patched build under
# ~/chromium/src/out/ja4-stable/. macOS Chromium-Sandbox needs the
# Helper bundles (Chromium Helper.app etc.) to be code-signed with
# matching entitlements; the unsigned developer build can't satisfy
# that, so the renderer process crashes on launch ("Failed to get
# task port") if the sandbox is enabled. Trade-off: Chromium shows
# a permanent "You are using an unsupported command-line flag"
# infobar at the top of every window. That banner is emitted by
# Chromium itself (not by this GUI) and there is no flag to silence
# it without also removing --no-sandbox; the only escape would be
# code-signing the patched build, which is out of scope here.
BROWSER_EXTRA_DEFAULT_ARGS=(--no-sandbox)
BROWSER_DEFAULT_URL=""
BROWSER_BUILD_HINT="scripts/build_chromium_with_patched_boringssl.sh"
