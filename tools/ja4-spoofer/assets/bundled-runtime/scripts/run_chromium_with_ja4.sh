#!/usr/bin/env bash
exec "$(dirname "${BASH_SOURCE[0]}")/run_browser.sh" --browser chromium "$@"
