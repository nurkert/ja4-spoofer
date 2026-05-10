# OpenSSL JA4 Config

This documents the current OpenSSL JA4 runtime hook used by `scripts/run_curl_with_ja4.sh`.

Important:

- This repo now supports two verified runtime paths:
  - the bundled `openssl` CLI from `scripts/build_openssl.sh`
  - a standalone `curl` built against the patched OpenSSL via `scripts/build_curl_with_openssl.sh`
- `scripts/run_curl_with_ja4.sh` prefers the built `curl` automatically when it exists and no explicit `--binary` or `--openssl` override is passed.
- The launcher no longer silently falls back to system `curl` for verification.

## Scope

The OpenSSL path is still not at NSS parity, but the current implementation now provides a robust runtime replay path with:

- config loading via `OPENSSL_JA4_CONFIG`
- dump output via `OPENSSL_JA4_DUMP`
- early ClientHello apply hook in `ssl/statem/statem_clnt.c`
- cipher list override in `ssl_cipher_list_to_bytes()`
- ALPN override
- signature algorithms override
- SNI suppression
- strict exact-mode toggle
- extension-order reorder/exact over built-in ClientHello extensions
- explicit overrides for `supported_versions`
- explicit overrides for `supported_groups`
- explicit overrides for `key_share_groups`
- explicit overrides for `psk_key_exchange_modes`
- GREASE value generation with extension/sigalg emission support
- effective dump of final cipher, extension, and TLS 1.3 JA4-relevant field order

## Supported Keys

Supported now:

- `tls_min`
- `tls_max`
- `strict`
- `cipher_suites`
- `cipher_mode`
- `alpn`
- `signature_algorithms`
- `extension_order`
- `extension_mode`
- `sni_mode`
- `enable_grease`
- `supported_versions`
- `supported_groups`
- `key_share_groups`
- `psk_key_exchange_modes`
- `enable_ch_xtn_permutation`

Behavior notes:

- `enable_grease` picks a random RFC 8701 GREASE value per handshake and can emit GREASE in signature-algorithm and extension ordering paths. It is not a full wire-level GREASE rewrite of every OpenSSL-internal list.
- `extension_mode=exact` supports strict replay and normalization for JA4-visible extension lists. If SNI/ALPN are configured but omitted from `extension_order` (common in JA4 strings), OpenSSL inserts `server_name (0)` and `alpn (16)`.

Not yet supported:

- a guaranteed-safe global `extension_mode=exact` that preserves all protocol-critical OpenSSL internals
- post-serialization regeneration of `key_share` entries (see Phase 3 below)

## Semantics

`cipher_mode`:

- `reorder`: configured ciphers are emitted first if OpenSSL can actually offer them; the remaining enabled ciphers follow in OpenSSL order
- `exact`: only configured ciphers are emitted, subject to OpenSSL's own disabled-cipher checks

`extension_mode`:

- `reorder`: configured built-in extensions are emitted first, remaining built-in extensions follow in OpenSSL order
- `exact`: configured built-in extensions are replayed in configured order. With `strict=1`, fallback preserve logic is disabled. JA4-visible lists are normalized by inserting `server_name (0)` and `alpn (16)` when required.

`sni_mode`:

- `none` and `ip` suppress the `server_name` extension
- `present` and `domain` currently fall back to normal OpenSSL hostname behaviour

## Important Limits

- The current extension reordering only covers built-in OpenSSL ClientHello extensions.
- Custom extensions are still added before the built-in block.
- The current implementation does not yet do a final wire-level rewrite after OpenSSL serialization.
- `supported_groups` and `key_share_groups` are independently configurable, but inconsistent combinations can still lead to failed or pruned offers because OpenSSL enforces its own internal validity checks.
- `psk_key_exchange_modes` is configurable, but this does not by itself create a full PSK resumption replay path.
- A repo-local `curl` linked against the patched OpenSSL can now be built and used for end-to-end verification. The bundled `openssl` CLI remains the lower-level debugging path.

## Diagnostic Schema v1

The OpenSSL JA4 hook implements the cross-library Diagnostic Schema v1
defined in [`docs/ja4-diagnostic-schema.md`](ja4-diagnostic-schema.md). The
schema is the authoritative contract for the `OPENSSL_JA4_DUMP` output: the
dump exposes a fixed `apply_ok`/`mismatch_mask` header, a `requested_*` block
echoing the configured overrides, and a `final_*` block with the values
observed during ClientHello construction. The OpenSSL hook is the only
writer of the dump; do not introduce additional keys outside the schema.

`mismatch_mask` is a `uint32_t` bitmask. The bits used by the OpenSSL hook
are:

| Bit | Hex | Name | Trigger |
|---|---|---|---|
| 0 | `0x0001` | `parse_error` | reserved for future config-syntax errors |
| 1 | `0x0002` | `apply_runtime_mismatch` | reserved for explicit apply-path failures |
| 2 | `0x0004` | `key_share_mismatch` | `final_key_share_groups != requested_key_share_groups` |
| 3 | `0x0008` | `supported_versions_mismatch` | `final_supported_versions != requested_supported_versions` |
| 4 | `0x0010` | `unknown_config_key` | parser saw an unknown key in `OPENSSL_JA4_CONFIG` |
| 5 | `0x0020` | `invalid_config_combination` | reserved for inconsistent-config detection |
| 6 | `0x0040` | `missing_requested_extension` | reserved for `extension_mode=exact` enforcement |
| 7 | `0x0080` | `cipher_suites_mismatch` | `final_cipher_suites != requested_cipher_suites` |
| 8 | `0x0100` | `alpn_mismatch` | `final_alpn != requested_alpn` |
| 9 | `0x0200` | `signature_algorithms_mismatch` | `final_signature_algorithms != requested_signature_algorithms` |
| 10 | `0x0400` | `extension_order_mismatch` | `final_extension_order != requested_extension_order` (modulo trailing PSK) |
| 11 | `0x0800` | `supported_groups_mismatch` | `final_supported_groups != requested_supported_groups` |
| 12 | `0x1000` | `psk_key_exchange_modes_mismatch` | `final_psk_key_exchange_modes != requested_psk_key_exchange_modes` |

`apply_ok` is `1` exactly when `mismatch_mask == 0`.

### Strict-Vertrag

With `strict=1`, a non-zero `mismatch_mask` after ClientHello construction
forces a hard handshake abort. The dump is still written (with the bits
set) so `OPENSSL_JA4_DUMP` remains usable for diagnostics. Without
`strict`, the bits are informational only and the handshake proceeds.

## Phase 2 Parity

The OpenSSL hook implements the same Phase-2 contracts as the NSS and
BoringSSL patches:

### `enable_ch_xtn_permutation`

The parser accepts `enable_ch_xtn_permutation=<0|1>` and round-trips the
value through the dump. When set to `1`, the post-serialization hook in
`ossl_ja4_rewrite_client_hello_wire` reorders the ClientHello extension
block in place using a Fisher-Yates shuffle driven by xorshift32, seeded
from `grease_value` (or an FNV-1a hash of `extension_order` when GREASE
is unset, so the result stays reproducible across runs). The same-size
invariant is preserved — only whole `(type, len, body)` tuples are
moved. RFC 8446 § 4.2.11 keeps `pre_shared_key` (0x0029) last, and
`padding` (0x0015) is treated as a fixed-tail entry to avoid breaking
downstream length math (length re-balancing after permutation is a
documented sub-limit, mirroring NSS). On parse failure or OOM the hook
raises `0x0020` (`invalid_config_combination`); strict mode then aborts.
The default value (when the key is absent) is `0`.

### Wire-Emission-Validation

After `tls_construct_extensions` finishes, the hook walks the captured
`final_extensions` list (populated by `ossl_ja4_note_extension` while the
WPACKET is built). When `extension_mode=exact` is active, every entry of
`requested_extension_order` must appear in the emitted set; any missing
entry raises bit `0x0040` (`missing_requested_extension`) before
`finalize_mismatches` latches `apply_ok`, so a missed extension correctly
fails the strict path and clears `apply_ok=0` in the dump.

### Auto-Inject Closure for `extension_mode=exact`

The configured `extension_order` is silently extended with extension types
that are implied by other set knobs, so a JA4-style replay that omits the
matching extension from the order list still produces a syntactically
valid ClientHello and does not trigger the 0x0400 drift bit:

| When set | Auto-injected extension |
|---|---|
| `signature_algorithms` | `0x000d` (`signature_algorithms`) |
| `supported_groups` | `0x000a` (`supported_groups`) |
| `key_share_groups` | `0x0033` (`key_share`) |
| `supported_versions` | `0x002b` (`supported_versions`) |
| `psk_key_exchange_modes` | `0x002d` (`psk_key_exchange_modes`) |
| `alpn` | `0x0010` (`application_layer_protocol_negotiation`) |
| `sni_mode` not in `{none,ip}` | `0x0000` (`server_name`) |

Auto-injection is silent (no mismatch bit). If, after apply, a body
override (e.g. `signature_algorithms`) is configured but the extension is
still not emitted on the wire, bit `0x0040`
(`missing_requested_extension`) fires via the wire-emission validation
above.

## Phase 3 Wire-Rewrite

Patch `0002-openssl-ja4-tls13-body-rewrite.patch` adds a post-serialization
ClientHello rewrite stage that mirrors the NSS helper
`ssl3_Ja4RewriteTls13ExtensionBodies` (NSS patch 0005). After
`tls_construct_extensions` finishes building the ClientHello body, but
before the outer u24 ClientHello-length sub-packet is closed by the
state-machine write-loop, OpenSSL now calls
`ossl_ja4_rewrite_client_hello_wire(s, pkt)` from
`tls_construct_client_hello`. The hook:

1. Calls `WPACKET_fill_lengths` so every closed sub-packet has its length
   prefix written to the underlying `BUF_MEM`.
2. Locates the ClientHello body in `pkt->buf->data` (skip
   `htype + u24-length` = 4 bytes), parses
   `legacy_version + random + session_id + cipher_suites +
    legacy_compression_methods + extensions`, and finds the u16 extension
   block.
3. Walks the extension block and, for each configured override, replaces
   the matching extension body byte-for-byte.
4. Re-captures `final_supported_versions`, `final_supported_groups`,
   `final_psk_key_exchange_modes` and `final_key_share_groups` from the
   post-rewrite buffer (analogous to BoringSSL's
   `ssl_ja4_capture_client_hello`).

### Rewritten extension IDs

| ID (hex) | Name | Body layout written |
|---|---|---|
| `0x002b` | `supported_versions` | `uint8 list_length + uint16[] versions` (ClientHello variant) |
| `0x000a` | `supported_groups` | `uint16 list_length + uint16[] groups` |
| `0x002d` | `psk_key_exchange_modes` | `uint8 list_length + uint8[] modes` |

The ServerHello variant of `supported_versions` (single `uint16`) is never
touched - the hook only fires in `tls_construct_client_hello`.

### Padding behaviour

This iteration only performs **same-size** in-place rewrites. If the new
body has a different length than the body OpenSSL serialized, the rewrite
is **skipped** and the corresponding mismatch bit
(`0x0008` / `0x0800` / `0x1000`) is raised. Under `strict=1` the handshake
aborts; otherwise the dump records the gap and OpenSSL keeps the original
serialization. Because the OpenSSL Phase-2 apply path already steers the
internal builders to honour `supported_versions`, `supported_groups` and
`psk_key_exchange_modes`, the same-size constraint is met for the vast
majority of replays. The optional `padding` extension (`0x0015`) emitted
by OpenSSL is **not** resized in this iteration; if a future override
needs delta-length rewrites we will add a length-balancing pass that
consumes the padding body, mirroring NSS' `ssl_InsertPaddingExtension`
fixup.

### Diff to the NSS implementation

| Aspect | NSS (`ssl3_Ja4RewriteTls13ExtensionBodies` + `ssl3_Ja4FinalizeClientExtensions`) | OpenSSL (this patch) |
|---|---|---|
| Buffer model | `sslBuffer` re-allocated per rewrite | `BUF_MEM` patched in place via `pkt->buf->data` |
| Body assembly | `sslBuffer_AppendNumber` chains | local stack buffer + `memcpy` |
| Length adjustment | `sslBuffer` grows/shrinks freely; padding size compensated post-rewrite | same-size only; no resize, no padding compensation |
| `key_share` regeneration | `ssl3_Ja4FindEphemeralKeyPair` + `tls13_EncodeKeyShareEntry` regenerates per group | not implemented; `OSSL_JA4_MISMATCH_KEY_SHARES` raised when override is configured |
| ECH-aware finalize | `ssl3_Ja4FinalizeClientExtensions` runs after ECH outer-CH and padding | OpenSSL has no ECH; hook fires once after `tls_construct_extensions` |
| PSK-last enforcement | `ssl3_Ja4EnsurePskExtensionLast` | not yet needed - OpenSSL's PSK builder already runs last when PSK is enabled |

### Known limits / residual risk

- **`key_share` is not regenerated.** Recreating an `EVP_PKEY` per
  configured group inside the rewrite stage is non-trivial because the
  matching private key must also be wired into `s->s3.tmp` so the
  subsequent KEM finalisation succeeds. If `key_share_groups` is
  configured but the on-wire `key_share` extension is missing, the hook
  raises `OSSL_JA4_MISMATCH_KEY_SHARES (0x0004)`; with `strict=1` this
  aborts, otherwise the bit is informational.
- **DTLS path is skipped.** The hook returns early when
  `SSL_CONNECTION_IS_DTLS(s)` is true; DTLS ClientHellos use a different
  handshake header layout.
- **ECH compatibility.** OpenSSL upstream has no merged ECH ClientHello
  encryption path, so the hook does not need a post-ECH replay stage. If
  ECH is added later, the hook must move behind the ECH outer-CH
  emission, mirroring `ssl3_Ja4FinalizeClientExtensions` in NSS patch
  0008.
- **No length-balancing padding pass yet.** A different-size body
  override is currently dropped (with the matching bit raised) instead of
  being absorbed by the padding extension.

## Dump Format

When `OPENSSL_JA4_DUMP` is set, OpenSSL writes a simple effective snapshot including:

- active state
- effective TLS min/max
- requested cipher list
- final emitted cipher list
- requested supported versions
- final emitted supported versions
- requested supported groups
- final emitted supported groups
- requested key share groups
- final emitted key share groups
- requested PSK key exchange modes
- final emitted PSK key exchange modes
- requested extension order
- final emitted extension order
- requested ALPN
- requested signature algorithms
- final signature algorithms
- strict mode / GREASE state

Example:

```ini
active=1
effective_tls_min=771
effective_tls_max=772
strict=1
enable_grease=0
requested_cipher_suites=4865,4866,4867
final_cipher_suites=4865,4866,4867,49199
requested_alpn=h2,http/1.1
requested_signature_algorithms=1027,1283,1539
final_signature_algorithms=1027,1283,1539
requested_supported_versions=772,771
final_supported_versions=772,771
requested_supported_groups=29,23
final_supported_groups=29,23
requested_key_share_groups=29
final_key_share_groups=29
requested_psk_key_exchange_modes=1
final_psk_key_exchange_modes=1
requested_extension_order=0,16,13
final_extension_order=0,16,13,10,43,45,51
```

## Verification

Dry-run:

```bash
scripts/run_curl_with_ja4.sh \
  --show-config \
  --dry-run \
  --tls-min 1.2 \
  --tls-max 1.3 \
  --cipher-suites 4865,4866,4867 \
  --cipher-mode exact \
  --openssl -- s_client -connect example.com:443 -servername example.com
```

Live test:

```bash
scripts/run_curl_with_ja4.sh \
  --openssl \
  --dump /tmp/openssl-ja4-effective.conf \
  --tls-min 1.2 \
  --tls-max 1.3 \
  --cipher-suites 4865,4866,4867 \
  --cipher-mode exact \
  --supported-versions 772,771 \
  --supported-groups 29,23 \
  --key-share-groups 29 \
  --psk-key-exchange-modes 1 \
  --extension-order 43,10,51,45 \
  --extension-mode reorder \
  -- s_client -connect example.com:443 -servername example.com
```

Observed phase-2/3 verification:

- `supported_versions=772,771` was emitted exactly in that order
- `supported_groups=29,23` was emitted exactly in that order
- `key_share_groups=29` restricted the emitted key share list to X25519 only
- `psk_key_exchange_modes=1` was emitted and recorded in the effective dump
- `extension_mode=reorder` completed a real handshake against a public HTTPS endpoint
- `extension_mode=exact` with requested `43,10,51,45` now completes a real handshake and results in the final emitted order `43,10,51,45,0,13`
- this confirms the current phase-3 strategy: keep exact replay narrow, but preserve the minimal OpenSSL handshake-critical extensions instead of silently falling back to broad reorder semantics

Live test with the repo-built `curl`:

```bash
scripts/build_curl_with_openssl.sh --jobs 8

scripts/run_curl_with_ja4.sh \
  --dump /tmp/openssl-ja4-effective.conf \
  --tls-min 1.2 \
  --tls-max 1.3 \
  --cipher-suites 4865,4866,4867 \
  --cipher-mode exact \
  --supported-versions 772,771 \
  --supported-groups 29,23 \
  --key-share-groups 29 \
  --psk-key-exchange-modes 1 \
  --extension-order 43,10,51,45 \
  --extension-mode exact \
  -- https://example.com
```

Observed repo-built `curl` verification:

- baseline request against a JA4 observation endpoint succeeded
- exact constrained request against the same endpoint succeeded
- the exact-mode dump matched the requested overrides:
  - `final_cipher_suites=4865,4866,4867`
  - `final_supported_versions=772,771`
  - `final_supported_groups=29,23`
  - `final_key_share_groups=29`
  - `final_psk_key_exchange_modes=1`
  - `final_extension_order=43,10,51,45,0,13`

This is intentionally not a browser-like JA4. It is a proof that the repo-built `curl` path now honors the configured OpenSSL JA4 overrides end to end.

Zen-style parity replay example:

```bash
scripts/run_curl_with_ja4.sh \
  --dump /tmp/openssl-ja4-effective.conf \
  --tls-min 1.2 \
  --tls-max 1.3 \
  --strict 1 \
  --cipher-suites 47,53,156,157,4865,4866,4867,49161,49162,49171,49172,49195,49196,49199,49200,52392,52393 \
  --cipher-mode exact \
  --alpn h2,http/1.1 \
  --signature-algorithms 1027,1283,1539,2052,2053,2054,1025,1281,1537,515,513 \
  --extension-order 5,10,11,13,18,23,27,35,43,45,51,65281 \
  --extension-mode exact \
  --sni-mode domain \
  -- -sS https://example.com
```

Observed output:

- `t13d1714h2_5b57614c22b0_1e35bda89c33`
- even though `extension_order` omits 0/16 (JA4-visible style), effective dump shows normalized replay order:
  - `requested_extension_order=0,5,10,11,13,16,18,23,27,35,43,45,51,65281`
  - `final_extension_order=0,5,10,11,13,16,18,23,27,35,43,45,51,65281`

Custom `curl` linked against the patched OpenSSL build:

```bash
scripts/run_curl_with_ja4.sh \
  --binary /path/to/curl \
  --dump /tmp/openssl-ja4-effective.conf \
  --tls-min 1.2 \
  --tls-max 1.3 \
  --cipher-suites 4865,4866,4867 \
  --cipher-mode exact \
  -- https://example.com
```
