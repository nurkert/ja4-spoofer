# BoringSSL JA4 Runtime Hook

This document describes the current BoringSSL runtime JA4 control path used by:

- `scripts/run_chromium_with_ja4.sh`
- `scripts/run_browser.sh --browser chromium`

## Environment Variables

- `BORINGSSL_JA4_CONFIG=/path/to/config.conf`
- `BORINGSSL_JA4_DUMP=/path/to/effective.conf`

## Supported Config Keys

The parser accepts the same key/value format as the launcher-generated config:

- `tls_min`
- `tls_max`
- `strict`
- `cipher_suites`
- `cipher_mode` (`reorder` / `exact`)
- `alpn`
- `signature_algorithms`
- `supported_versions`
- `supported_groups`
- `key_share_groups`
- `psk_key_exchange_modes`
- `extension_order`
- `extension_mode` (`reorder` / `exact`)
- `sni_mode` (`present` / `domain` / `none` / `ip`)
- `enable_grease`
- `enable_ch_xtn_permutation`

## Implemented Behavior

- Early handshake hook: JA4 config is parsed before ECH/key-share/client-hello generation.
- `strict=1` hard-fails on invalid runtime config (instead of best-effort fallback):
  - unknown config keys
  - parse errors
  - `cipher_mode=exact` without `cipher_suites`
  - `extension_mode=exact` without `extension_order`
  - invalid version range (`tls_min > tls_max`)
- Cipher replay:
  - `exact`: emit configured cipher list in given order.
  - `reorder`: emit configured ciphers first, then remaining defaults.
- Extension replay:
  - custom deterministic order via `extension_order`.
  - `exact`: non-requested built-in extensions are skipped.
  - `exact` now validates dependency closure (for example ALPN/sigalgs/groups/key_share/supported_versions/psk modes) and
    reports strict failures instead of silently drifting.
  - `exact` now validates that requested extensions were actually emitted on wire; missing ones set mismatch and fail in strict mode.
  - `pre_shared_key` is handled as a special-case extension and normalized to last position.
  - `reorder`: requested extension order first, then remaining defaults.
- `supported_versions` override is applied in `ssl_add_supported_versions`.
- `psk_key_exchange_modes` override is applied in client extension writer.
- GREASE can be forced on/off per run (`enable_grease`), independent of global context default.
- Dump output is written from the final serialized ClientHello, so `final_*` fields reflect on-wire values.

## Dump Output

`BORINGSSL_JA4_DUMP` includes:

- activation and apply status (`active`, `apply_ok`, `mismatch_mask`)
- effective version range and knobs (`effective_tls_*`, `strict`, `sni_mode`, grease/permutation)
- requested vs final emitted lists:
  - ciphers
  - signature algorithms
  - extension order
  - supported versions
  - supported groups
  - key share groups
  - psk key exchange modes

`mismatch_mask` bits:

- `1` parse error
- `2` apply/runtime mismatch
- `4` key-share mismatch
- `8` supported-versions mismatch
- `16` unknown config key
- `32` invalid config combination
- `64` exact-mode dependency missing (requested runtime knobs need an extension that is absent or not emitted)
- `128` (`0x0080`) cipher suites drift (`final_cipher_suites != requested_cipher_suites`)
- `256` (`0x0100`) ALPN drift (`final_alpn != requested_alpn`)
- `512` (`0x0200`) signature algorithms drift (`final_signature_algorithms != requested_signature_algorithms`)
- `1024` (`0x0400`) extension order drift (`final_extension_order != requested_extension_order`, modulo PSK-Last-Normalisierung)
- `2048` (`0x0800`) supported groups drift (`final_supported_groups != requested_supported_groups`)
- `4096` (`0x1000`) PSK key exchange modes drift (`final_psk_key_exchange_modes != requested_psk_key_exchange_modes`)

## Diagnostic Schema v1

The dump output now follows the cross-library `JA4 Diagnostic Schema v1`
defined in [`docs/ja4-diagnostic-schema.md`](./ja4-diagnostic-schema.md).
That document is the single source of truth for:

- the `mismatch_mask` bit layout (bits 0..12, the new bits 7..12 listed
  above are byte-structurally aligned with NSS and OpenSSL);
- the dump key set and ordering (full `requested_*` block before the full
  `final_*` block, schema-defined intra-block order);
- the strict contract: under `strict=1` any non-zero `mismatch_mask` causes
  a hard handshake abort. The dump is still written so callers can diagnose
  the failure.

The drift bits (`0x0080`..`0x1000`) are populated by
`ssl_ja4_capture_client_hello`, which re-parses the serialized ClientHello
and compares the on-wire lists against the corresponding `requested_*`
override. Setting these bits is purely diagnostic; no apply-path was
changed by this comparison.

## Phase 2 Parity

Phase 2 closes two gaps where BoringSSL's native builders would otherwise
silently drop a JA4-requested extension. Both gates require the extension
to be **explicitly listed** in `extension_order` and `extension_mode` to
be `exact` or `reorder`; otherwise BoringSSL falls back to its default
behavior with no JA4 interference.

### Force-Emit of normally suppressed extensions

When the native `kExtensions[i].add_clienthello` builder writes 0 bytes
for one of the IDs below, `ssl_ja4_force_emit_native_if_needed` emits a
minimal RFC-compliant stub at the same position so the on-wire
`final_extension_order` matches `requested_extension_order`.

| ID (hex) | ID (dec) | Name | Forced body |
|---|---|---|---|
| `0x0005` | 5 | `status_request` | `01 00 00 00 00` (OCSP status type, empty responder list, empty extensions) |
| `0x0012` | 18 | `signed_certificate_timestamp` | empty |
| `0x0023` | 35 | `session_ticket` | empty (announce support, no ticket) |
| `0x0016` | 22 | `encrypt_then_mac` | empty (no native BoringSSL builder; force = synthetic header) |
| `0x0015` | 21 | `padding` | one zero byte |
| `0x0031` | 49 | `post_handshake_auth` | empty |
| `0x0022` | 34 | `delegated_credentials` | empty body (announce support, no DC sigschemes) |
| `0xfdf9` | 65037 | `encrypted_client_hello` | GREASE outer-CH stub when no ECHConfigList is configured |

If neither a native builder nor a synthetic stub is available for a
requested ID, the validator sets bit `0x40`
(`missing_requested_extension`) on `mismatch_mask`.

### Synthetic-Extension Constructor

`ja4_emit_synthetic_extension` injects extensions that have no native
BoringSSL builder. Emission happens after the native-builder loop and
before GREASE2 / F5-padding / PSK-last normalization; the IDs are
appended to `hs->ja4.synthetic_sent` so
`ssl_ja4_validate_requested_extensions_sent` does not flag them as
missing.

| ID (hex) | ID (dec) | Name | Body |
|---|---|---|---|
| `0x001c` | 28 | `record_size_limit` | `40 01` (16385, big-endian u16) |
| `0x001b` | 27 | `compress_certificate` | `06 00 02 00 01 00 02` (u8 list-length, three u16 algorithms; mirrors the OpenSSL stub) |
| `0x0022` | 34 | `delegated_credentials` | empty body |
| any other unknown ID | — | generic stub | empty body |

The synthetic constructor never overrides a successful native builder —
the helper bails out early if `tls_extension_find` returns a non-null
table entry.

### Wire-Tail GREASE in `signature_algorithms`

The JA4 third hash (sigalgs) is computed from the wire bytes literally,
without GREASE stripping. To match the OpenSSL/NSS layout, the patch
appends a single trailing GREASE marker
(`ssl_get_grease_value(hs, ssl_grease_extension1)`) to the sigalgs
extension body when `enable_grease=1`. The diagnostic compare for
`signature_algorithms` is relaxed to the modulo-grease helper so the
wire-only GREESE entry does not trigger `0x0200` drift.

### Cipher- and Group-Filter Bypass

When `cipher_mode=exact` is in effect, BoringSSL's default
`compliance_policy`/SSL-config path no longer prepends an additional
GREASE cipher; the GREASE seed slot still rides the wire when
`enable_grease=1` is set. For `supported_groups`, the wire-time
`SSLKeyShare::Create()` whitelist is bypassed when the JA4 config
supplies an exact list, so legacy-but-named groups (e.g. `secp192r1`)
survive intact.

### Standalone GREESE-Extension Gate

`ssl_ja4_should_emit_standalone_grease_extensions` suppresses the
duplicate GREASE1/GREASE2 standalone slots when `extension_order`
already encodes the GREESE positions explicitly. The helper allows the
fallback path when `extension_mode != exact` so non-exact replays keep
BoringSSL's native GREESE diversity.

### `psk_key_exchange_modes` Auto-Inject

When `psk_key_exchange_modes` is non-empty, extension 45 is
auto-appended to `extension_order` so the configured value always lands
on the wire even if the runtime config did not list the extension
explicitly.

## Known Limits

- Key shares cannot be generated for unknown/unsupported groups; such entries cannot be fully replayed as key_share payloads.
- `extension_mode=exact` can intentionally produce handshake-incompatible ClientHellos if mandatory extensions are omitted.
- Some extension IDs are conditional on runtime/session state (for example resumption/feature flags); requesting them in strict exact mode can fail fast if BoringSSL does not emit them in this handshake.
- Full Chromium-level verification still depends on a local Chromium/BoringSSL build environment.
- Phase 2 force-emit/synthetic stubs are intentionally minimal — they
  achieve byte-positional parity but do not negotiate real semantics
  (for example a forced `status_request` will not actually request OCSP
  responses from the server). Phase 3 may upgrade selected stubs to
  semantically meaningful payloads.
