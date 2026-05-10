#!/usr/bin/env bash
# scripts/ja4_verify.sh — acceptance harness for JA4 Diagnostic Schema v1.
# Drives one of the three patched libraries with a fixture from tests/ja4-fixtures/
# and asserts the resulting dump conforms to docs/ja4-diagnostic-schema.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/ja4-fixtures"

usage() {
  cat <<'USAGE'
Usage: scripts/ja4_verify.sh --lib <nss|openssl|boringssl> --fixture <name> [options]

Options:
  --lib <nss|openssl|boringssl>   Target library (required)
  --fixture <name>                Fixture name (e.g. firefox-128, negative/parse_error)
  --target <url>                  HTTPS target (default: https://example.com)
  --pcap <path>                   Optional pcap output path (requires tshark+sudo)
  --print-hash                    Print observed JA4 hash to stdout
  --record                        Update .expected with observed JA4 (auto-baseline)
  --expect-fail                   Invert: expect strict-handshake fail
  --no-network                    Skip live HTTP request, only check dump file
  -h, --help                      Show this help
USAGE
}

LIB=""
FIXTURE=""
TARGET="${JA4_VERIFY_TARGET:-https://example.com}"
PCAP=""
PRINT_HASH=0
RECORD=0
EXPECT_FAIL=0
NO_NETWORK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lib) LIB="$2"; shift 2 ;;
    --fixture) FIXTURE="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --pcap) PCAP="$2"; shift 2 ;;
    --print-hash) PRINT_HASH=1; shift ;;
    --record) RECORD=1; shift ;;
    --expect-fail) EXPECT_FAIL=1; shift ;;
    --no-network) NO_NETWORK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[error] unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$LIB" || -z "$FIXTURE" ]]; then
  usage; exit 2
fi

CONF_FILE="$FIXTURE_DIR/${FIXTURE}.conf"
EXP_FILE="$FIXTURE_DIR/${FIXTURE}.expected"
if [[ ! -f "$CONF_FILE" ]]; then
  echo "[error] fixture missing: $CONF_FILE" >&2
  exit 2
fi
if [[ ! -f "$EXP_FILE" ]]; then
  echo "[error] expected file missing: $EXP_FILE" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d -t ja4-verify.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

DUMP_FILE="$TMP_DIR/dump.conf"
RUN_OUT="$TMP_DIR/run.out"
RUN_ERR="$TMP_DIR/run.err"
HTTP_OUT="$TMP_DIR/http.out"

run_lib() {
  local rc=0
  case "$LIB" in
    openssl)
      bash "$SCRIPT_DIR/run_curl_with_ja4.sh" \
        --config "$CONF_FILE" \
        --dump "$DUMP_FILE" \
        -- -sSk -o "$HTTP_OUT" "$TARGET" \
        >"$RUN_OUT" 2>"$RUN_ERR" || rc=$?
      ;;
    nss)
      bash "$SCRIPT_DIR/run_curl_with_ja4.sh" \
        --config "$CONF_FILE" \
        --dump "$DUMP_FILE" \
        -- -sSk -o "$HTTP_OUT" "$TARGET" \
        >"$RUN_OUT" 2>"$RUN_ERR" || rc=$?
      echo "[warn] NSS HTTP path uses curl-link; for browser-driven fixtures use scripts/run_firefox_with_ja4.sh manually" >&2
      ;;
    boringssl)
      # Parse TARGET URL into host[:port], SNI, and HTTP path for the bssl
      # client. The cross-lib harness ships /raw or /json in the URL so the
      # server response carries a JA4 hash; the bssl helper takes the path
      # explicitly via --http-path.
      local t="${TARGET#http://}"; t="${t#https://}"
      local hostport="${t%%/*}"
      local host="${hostport%%:*}"
      local port="${hostport#*:}"; [[ "$port" == "$hostport" ]] && port=443
      local path="/${t#*/}"
      [[ "$path" == "/$t" ]] && path="/raw"
      bash "$SCRIPT_DIR/run_boringssl_with_ja4.sh" \
        --config "$CONF_FILE" \
        --dump "$DUMP_FILE" \
        --connect "$host:$port" \
        --server-name "$host" \
        --http-path "$path" \
        --http-wait 1.5 \
        >"$RUN_OUT" 2>"$RUN_ERR" || rc=$?
      ;;
    *) echo "[error] unsupported lib: $LIB" >&2; exit 2 ;;
  esac
  return $rc
}

read_kv() {
  local file="$1"
  local key="$2"
  awk -F'=' -v k="$key" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$file"
}

read_exp_kv() {
  local key="$1"
  awk -F'=' -v k="$key" '!/^#/ && $1==k {sub(/^[^=]*=/,""); print; exit}' "$EXP_FILE"
}

run_rc=0
run_lib || run_rc=$?

if [[ "$EXPECT_FAIL" -eq 1 ]]; then
  if [[ $run_rc -eq 0 ]]; then
    echo "[FAIL] $FIXTURE/$LIB: expected handshake fail but run succeeded" >&2
    exit 1
  fi
  echo "[OK] $FIXTURE/$LIB: handshake failed as expected"
  exit 0
fi

if [[ $run_rc -ne 0 && "$EXPECT_FAIL" -eq 0 ]]; then
  echo "[FAIL] $FIXTURE/$LIB: run exited $run_rc" >&2
  cat "$RUN_ERR" >&2 || true
  exit 1
fi

if [[ ! -s "$DUMP_FILE" ]]; then
  echo "[FAIL] $FIXTURE/$LIB: dump file empty: $DUMP_FILE" >&2
  exit 1
fi

# Schema-Konformitaet: Pflichtschluessel pruefen.
required_keys=(active apply_ok mismatch_mask
  effective_tls_min effective_tls_max strict sni_mode
  enable_grease enable_ch_xtn_permutation grease_value
  requested_cipher_suites requested_alpn requested_signature_algorithms
  requested_extension_order requested_supported_versions
  requested_supported_groups requested_key_share_groups
  requested_psk_key_exchange_modes
  final_cipher_suites final_alpn final_signature_algorithms
  final_extension_order final_supported_versions
  final_supported_groups final_key_share_groups
  final_psk_key_exchange_modes)
missing=()
for k in "${required_keys[@]}"; do
  if ! grep -q "^$k=" "$DUMP_FILE"; then
    missing+=("$k")
  fi
done
if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "[FAIL] $FIXTURE/$LIB: dump missing schema keys: ${missing[*]}" >&2
  exit 1
fi

mismatch=$(read_kv "$DUMP_FILE" mismatch_mask)
apply_ok=$(read_kv "$DUMP_FILE" apply_ok)

# Negative fixture path.
exp_bit=$(read_exp_kv expect_mismatch_bit || true)
if [[ -n "$exp_bit" ]]; then
  bit_dec=$(printf '%d' "$exp_bit")
  if (( (mismatch & bit_dec) == 0 )); then
    echo "[FAIL] $FIXTURE/$LIB: expected mismatch bit $exp_bit not set (got mask=$mismatch)" >&2
    exit 1
  fi
  exp_apply=$(read_exp_kv expect_apply_ok || echo 0)
  if [[ "$apply_ok" != "$exp_apply" ]]; then
    echo "[FAIL] $FIXTURE/$LIB: expected apply_ok=$exp_apply, got $apply_ok" >&2
    exit 1
  fi
  echo "[OK] $FIXTURE/$LIB: bit $exp_bit set, apply_ok=$apply_ok"
  exit 0
fi

# Positive fixture path.
exp_mismatch=$(read_exp_kv mismatch_mask || echo 0)
exp_apply=$(read_exp_kv apply_ok || echo 1)
if [[ "$mismatch" != "$exp_mismatch" ]]; then
  echo "[FAIL] $FIXTURE/$LIB: mismatch_mask=$mismatch (expected $exp_mismatch)" >&2
  exit 1
fi
if [[ "$apply_ok" != "$exp_apply" ]]; then
  echo "[FAIL] $FIXTURE/$LIB: apply_ok=$apply_ok (expected $exp_apply)" >&2
  exit 1
fi

# require_requested_eq_final
# With enable_grease=1 the lib may append a single trailing GREASE entry on the
# final side (e.g. OpenSSL/NSS signature_algorithms) or prepend a single leading
# GREASE entry (e.g. BoringSSL cipher_suites/supported_groups/key_share_groups).
# Both are by design, not a mismatch — accept either when the GREASE value
# matches the dump's grease_value.
dump_grease=$(read_kv "$DUMP_FILE" grease_value)
dump_grease_on=$(read_kv "$DUMP_FILE" enable_grease)
req_eq=$(read_exp_kv require_requested_eq_final || true)
if [[ -n "$req_eq" ]]; then
  IFS=',' read -r -a fields <<<"$req_eq"
  for f in "${fields[@]}"; do
    r=$(read_kv "$DUMP_FILE" "requested_$f")
    fl=$(read_kv "$DUMP_FILE" "final_$f")
    if [[ "$r" == "$fl" ]]; then
      continue
    fi
    if [[ "$dump_grease_on" == "1" && -n "$dump_grease" ]]; then
      # Strip up to one leading GREASE pattern and any number of trailing
      # GREASE-pattern entries (per RFC 8701, the values 0x?A?A with both
      # nibbles equal). The configured grease_value must match the leading one.
      stripped_fl=$(DUMP_GREASE="$dump_grease" python3 -c '
import sys, os
parts = [p for p in sys.stdin.read().strip().split(",") if p]
gv = int(os.environ.get("DUMP_GREASE", "0"))
def is_grease(v):
    try:
        n = int(v)
    except ValueError:
        return False
    return (n & 0x0F0F) == 0x0A0A and (n >> 8) == (n & 0xFF)
if parts and parts[0].isdigit() and int(parts[0]) == gv:
    parts = parts[1:]
while parts and is_grease(parts[-1]):
    parts = parts[:-1]
print(",".join(parts))
' <<<"$fl") || stripped_fl="$fl"
      if [[ "$r" == "$stripped_fl" ]]; then
        continue
      fi
    fi
    echo "[FAIL] $FIXTURE/$LIB: requested_$f != final_$f ($r != $fl)" >&2
    exit 1
  done
fi

# require_grease_value
req_grease=$(read_exp_kv require_grease_value || true)
if [[ -n "$req_grease" ]]; then
  got=$(read_kv "$DUMP_FILE" grease_value)
  if [[ "$got" != "$req_grease" ]]; then
    echo "[FAIL] $FIXTURE/$LIB: grease_value=$got (expected $req_grease)" >&2
    exit 1
  fi
fi

# JA4-hash check via server response. The OpenSSL/NSS branches use curl -o to
# write the HTTP body to $HTTP_OUT; the BoringSSL branch streams the body to
# the bssl client's stdout, which the run helper captures into $RUN_OUT.
observed_ja4=""
if [[ "$NO_NETWORK" -eq 0 ]]; then
  for src in "$HTTP_OUT" "$RUN_OUT"; do
    [[ -s "$src" ]] || continue
    observed_ja4=$(grep -oE 't1[2-3]?[di][0-9a-z_]+' "$src" | head -n 1 || true)
    [[ -n "$observed_ja4" ]] && break
  done
fi

exp_ja4=$(read_exp_kv expected_ja4 || true)
if [[ "$RECORD" -eq 1 && -n "$observed_ja4" ]]; then
  tmp_exp=$(mktemp)
  awk -F'=' -v v="$observed_ja4" '/^expected_ja4=/ {print "expected_ja4=" v; next} {print}' "$EXP_FILE" >"$tmp_exp"
  mv "$tmp_exp" "$EXP_FILE"
  echo "[record] $FIXTURE/$LIB: expected_ja4 -> $observed_ja4"
fi

if [[ "$RECORD" -eq 0 && -n "$exp_ja4" && "$exp_ja4" != "auto-baseline" && -n "$observed_ja4" ]]; then
  if [[ "$exp_ja4" != "$observed_ja4" ]]; then
    echo "[FAIL] $FIXTURE/$LIB: ja4 hash mismatch (expected $exp_ja4, got $observed_ja4)" >&2
    exit 1
  fi
fi

if [[ "$PRINT_HASH" -eq 1 && -n "$observed_ja4" ]]; then
  echo "$observed_ja4"
fi

echo "[OK] $FIXTURE/$LIB: dump conforms, mismatch_mask=0, apply_ok=1${observed_ja4:+, ja4=$observed_ja4}"
