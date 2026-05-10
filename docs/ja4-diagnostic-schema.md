# JA4 Diagnostic Schema v1

This schema defines the diagnostic dump format written by the BoringSSL, NSS and
OpenSSL JA4 runtime hooks. The goal is that every stack emits the same keys, in
the same order, with the same meaning.

Related documents:

- [JA4 extension-content analysis](ja4.md)
- [BoringSSL JA4 runtime hook](boringssl-ja4-config.md)
- [NSS JA4 runtime hook](nss-ja4-config.md)
- [OpenSSL JA4 runtime hook](openssl-ja4-config.md)
- [Impersonation edge cases](impersonation-edge-cases.md)

## Scope

The schema covers diagnostic output (`*_JA4_DUMP`) for the initial ClientHello.
It does not define input config keys; those are documented per stack.

Session resumption ClientHellos are outside this schema.

## Mismatch Mask

`mismatch_mask` is a 32-bit integer. Bits 0-12 are currently defined:

| Bit | Hex | Name | Meaning |
|---|---|---|---|
| 0 | `0x0001` | `parse_error` | Config could not be parsed |
| 1 | `0x0002` | `apply_runtime_mismatch` | Requested override could not be applied to stack state |
| 2 | `0x0004` | `key_share_mismatch` | `key_share_groups` contains an unsupported or unreplayable group |
| 3 | `0x0008` | `supported_versions_mismatch` | `supported_versions` contains an unsupported version |
| 4 | `0x0010` | `unknown_config_key` | Parser saw an unknown config key |
| 5 | `0x0020` | `invalid_config_combination` | Config is semantically inconsistent |
| 6 | `0x0040` | `missing_requested_extension` | Requested exact extension is missing from the final ClientHello |
| 7 | `0x0080` | `cipher_suites_mismatch` | Final cipher suites differ from requested cipher suites |
| 8 | `0x0100` | `alpn_mismatch` | Final ALPN differs from requested ALPN |
| 9 | `0x0200` | `signature_algorithms_mismatch` | Final signature algorithms differ from requested values |
| 10 | `0x0400` | `extension_order_mismatch` | Final extension order differs from requested order |
| 11 | `0x0800` | `supported_groups_mismatch` | Final supported groups differ from requested groups |
| 12 | `0x1000` | `psk_key_exchange_modes_mismatch` | Final PSK modes differ from requested modes |

Bits 13-31 are reserved.

## Invalid Config Combinations

The `invalid_config_combination` bit is set for cases such as:

- `tls_min > tls_max`,
- `cipher_mode=exact` without a non-empty `cipher_suites`,
- `extension_mode=exact` without a non-empty `extension_order`,
- `key_share_groups` is not a subset of `supported_groups`,
- `enable_ch_xtn_permutation=1` on a stack that cannot permute extensions.

## `apply_ok`

```text
apply_ok = mismatch_mask == 0
```

The dump writes `apply_ok` as `0` or `1`.

When `strict=1`, a non-zero mismatch mask aborts the handshake. The dump should
still be written so the failure can be diagnosed.

## Dump Keys and Order

The dump is a flat newline-separated `key=value` file. Lists are comma-separated
without spaces. Empty lists are written as an empty value.

```text
active=<0|1>
apply_ok=<0|1>
mismatch_mask=<decimal>

effective_tls_min=<int>
effective_tls_max=<int>
strict=<0|1>
sni_mode=<present|domain|none|ip>
enable_grease=<0|1>
enable_ch_xtn_permutation=<0|1>
grease_value=<uint16-or-empty>

requested_cipher_suites=<csv>
requested_alpn=<csv>
requested_signature_algorithms=<csv>
requested_extension_order=<csv>
requested_supported_versions=<csv>
requested_supported_groups=<csv>
requested_key_share_groups=<csv>
requested_psk_key_exchange_modes=<csv>

final_cipher_suites=<csv>
final_alpn=<csv>
final_signature_algorithms=<csv>
final_extension_order=<csv>
final_supported_versions=<csv>
final_supported_groups=<csv>
final_key_share_groups=<csv>
final_psk_key_exchange_modes=<csv>
```

## Change Policy

- Bits 0-12 are frozen.
- New bits start at bit 13.
- Existing key order is frozen.
- New fields must be appended to the relevant block.
- Stack-specific diagnostics should use a separate `lib_*` block at the end.

## Verification

`scripts/ja4_verify.sh` checks:

- required keys and ordering,
- requested/final list parity,
- `apply_ok=1` and `mismatch_mask=0` for positive fixtures,
- expected mismatch bits for negative fixtures,
- expected JA4 values when an external JA4 observation is available.
