# NSS JA4 Runtime Hook

The NSS patch adds an optional runtime configuration path for ClientHello fields
that affect JA4. NSS reads a config file from `NSS_JA4_CONFIG` and can write the
effective result to `NSS_JA4_DUMP`.

## Environment Variables

```bash
NSS_JA4_CONFIG=/path/to/nss.conf
NSS_JA4_DUMP=/path/to/effective.conf
```

## Config Format

The config format is one `key=value` pair per line. `#` starts a comment.

```ini
strict=1
tls_min=1.2
tls_max=1.3
supported_versions=772,771
enable_grease=0
enable_ch_xtn_permutation=0
cipher_mode=exact
cipher_suites=4865,4867,4866,49195,49199
alpn=h2,http/1.1
signature_algorithms=1027,1283,1539,2052,2053
supported_groups=29,23,24
key_share_groups=29
psk_key_exchange_modes=1
extension_mode=exact
extension_order=0,23,65281,10,11,35,16,5,34,18,51,43,13,45,28
sni_mode=present
```

## Supported Keys

- `tls_min`, `tls_max`
- `strict`
- `cipher_suites`
- `cipher_mode` (`reorder`, `exact`)
- `alpn`
- `signature_algorithms` (`signature_schemes` alias)
- `supported_versions`
- `supported_groups`
- `key_share_groups`
- `psk_key_exchange_modes`
- `extension_order` (`extensions` alias)
- `extension_mode` (`reorder`, `exact`)
- `sni_mode` (`present`, `domain`, `none`, `ip`)
- `enable_grease`
- `enable_ch_xtn_permutation`

Boolean keys accept `0`, `1`, `true`, `false`, `on`, `off`, `yes`, `no`.

## Mode Semantics

| Key | Behavior |
|---|---|
| `cipher_mode=reorder` | Move requested ciphers to the front, keep remaining defaults |
| `cipher_mode=exact` | Emit only the requested cipher list where possible |
| `extension_mode=reorder` | Move requested extensions first, keep remaining defaults |
| `extension_mode=exact` | Emit only requested extensions, subject to protocol-required dependencies |
| `supported_versions` | Override the `supported_versions` extension body |
| `supported_groups` | Override named group preferences |
| `key_share_groups` | Select generated TLS 1.3 key-share groups |
| `psk_key_exchange_modes` | Override PSK mode values |

If `extension_order` is present without `extension_mode`, NSS treats it as
`reorder`.

## Strict Mode

With `strict=1`, NSS rejects invalid or drifting configurations instead of
silently falling back.

Strict checks include:

- unknown config keys,
- parse errors,
- `tls_min > tls_max`,
- `cipher_mode=exact` without a non-empty `cipher_suites`,
- `extension_mode=exact` without a non-empty `extension_order`,
- unsupported named groups,
- `key_share_groups` not being a subset of `supported_groups`,
- requested/final mismatches after ClientHello construction.

The dump is still written when strict mode aborts, so callers can inspect the
mismatch mask.

## Dependency Closure

When an exact extension order omits an extension required by a body override,
the NSS hook inserts that extension before `pre_shared_key` where necessary.

| Body override | Required extension ID |
|---|---|
| `signature_algorithms` | `13` |
| `supported_groups` | `10` |
| `key_share_groups` | `51` |
| `supported_versions` | `43` |
| `psk_key_exchange_modes` | `45` |
| `alpn` | `16` |
| `sni_mode != none` | `0` |

## Diagnostic Dump

`NSS_JA4_DUMP` follows [JA4 Diagnostic Schema v1](ja4-diagnostic-schema.md).
The important fields are:

- `apply_ok`,
- `mismatch_mask`,
- `requested_*`,
- `final_*`.

Use the dump to verify that the requested profile actually reached the wire.

## FCS Emitter Note

`scripts/fcs_emit.py --target nss` may emit only a subset of the full NSS
runtime keys. FCS profiles can still contain the broader fields for future
backends and GUI round-tripping.

## Firefox Automation Note

Full Firefox automation can fail before TLS starts because of browser startup,
profile or platform issues. When debugging the NSS hook itself, prefer the
library-level verification path and inspect `NSS_JA4_DUMP`.

## GREASE and Captured Replay

For captured profiles, the GUI forces:

```ini
enable_grease=0
enable_ch_xtn_permutation=0
```

This keeps captured replay deterministic and avoids wire drift. Manually edited
profiles can still enable GREASE for more browser-like live behavior.
