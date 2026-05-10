# Browser declaration: Firefox with patched NSS

BROWSER_NAME="Firefox"
BROWSER_BIN_ENV_VAR="FIREFOX_BIN"
BROWSER_BIN_OPTION="--firefox-bin"
BROWSER_SEARCH_PATHS=(
  "$HOME/build/firefox-ja4-stable/gecko-dev/obj-ja4-stable/dist/Firefox.app/Contents/MacOS/firefox"
  "$HOME/build/firefox-ja4-stable/gecko-dev/obj-ja4-stable/dist/Nightly.app/Contents/MacOS/firefox"
  "$HOME/build/firefox-ja4-stable/gecko-dev/obj-ja4-stable/dist/bin/firefox"
)
BROWSER_CONFIG_ENV_VARS=("NSS_JA4_CONFIG")
BROWSER_DUMP_ENV_VAR="NSS_JA4_DUMP"
BROWSER_DEFAULT_CONFIG_OUT="/tmp/nss-ja4-run.conf"
BROWSER_DEFAULT_DUMP_PATH="/tmp/nss-ja4-effective.conf"
BROWSER_PROFILE_FLAG="-profile"
BROWSER_PROFILE_FORMAT="flag"
BROWSER_EXTRA_DEFAULT_ARGS=("-no-remote")
BROWSER_DEFAULT_URL="about:blank"
BROWSER_BUILD_HINT="scripts/build_firefox_with_patched_nss.sh"
