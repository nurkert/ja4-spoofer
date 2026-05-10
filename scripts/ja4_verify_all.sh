#!/usr/bin/env bash
# JA4 cross-lib acceptance harness (Pflichtcheck 5).
# Iterates fixtures x libs through ja4_verify.sh and reports cross-lib
# parity. Use `record` mode to populate expected_ja4 in fixtures.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Usage: scripts/ja4_verify_all.sh [verify|record] [--target URL]

Env overrides:
  LIBS="openssl boringssl"                   # space-separated lib list
  FIXTURES="firefox-128 chrome-131 zen-1.x tor-13"
USAGE
}

mode="verify"
target_arg=()
if [[ ${1-} == "verify" || ${1-} == "record" ]]; then
  mode="$1"; shift || true
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) target_arg=(--target "$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[error] unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

read -r -a LIB_LIST <<<"${LIBS:-openssl boringssl}"
read -r -a FIX_LIST <<<"${FIXTURES:-firefox-128 chrome-131 zen-1.x tor-13}"

declare -A HASH

run_one() {
  local lib="$1" fix="$2"
  local extra=()
  [[ "$mode" == "record" ]] && extra+=(--record)
  local out
  if ! out=$(bash "$SCRIPT_DIR/ja4_verify.sh" --lib "$lib" --fixture "$fix" --print-hash "${extra[@]}" "${target_arg[@]}" 2>&1); then
    echo "[FAIL] $lib/$fix"
    printf '%s\n' "$out" | sed 's/^/    /'
    return 1
  fi
  printf '%s\n' "$out" | sed 's/^/    /'
  HASH["$fix:$lib"]=$(printf '%s\n' "$out" | grep -oE 't1[2-3]?[di][0-9a-z_]+' | head -n1 || true)
  return 0
}

fail=0
for fix in "${FIX_LIST[@]}"; do
  for lib in "${LIB_LIST[@]}"; do
    echo "== $lib/$fix =="
    run_one "$lib" "$fix" || fail=1
  done
done

echo
echo "== Cross-lib hash parity =="
for fix in "${FIX_LIST[@]}"; do
  uniq_count=$(for lib in "${LIB_LIST[@]}"; do echo "${HASH[$fix:$lib]-}"; done | sort -u | wc -l | tr -d ' ')
  ref_lib="${LIB_LIST[0]}"
  ref="${HASH[$fix:$ref_lib]-}"
  if [[ -z "$ref" ]]; then
    echo "[N/A]   $fix  (no hash captured)"
    continue
  fi
  if [[ "$uniq_count" == "1" ]]; then
    echo "[OK]    $fix  $ref"
  else
    echo "[DRIFT] $fix"
    for lib in "${LIB_LIST[@]}"; do
      echo "          $lib: ${HASH[$fix:$lib]-<none>}"
    done
  fi
done

exit "$fail"
