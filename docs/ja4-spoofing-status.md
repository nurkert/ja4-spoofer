# JA4 Patch Stack Status

This page tracks the public patch-stack state for the three supported TLS
libraries. For user-facing capability notes, see
[JA4 capabilities and limits](ja4-spoofing-summary.md).

## Sources of Truth

- `docs/ja4-diagnostic-schema.md`
- `patches/{nss,openssl,boringssl}/`
- `tests/ja4-fixtures/`
- `scripts/ja4_verify.sh`

## Patch Inventory

| Stack | Base ref source | Patch directory | Internals |
|---|---|---|---|
| NSS | `patches/nss/BASE_REF` | `patches/nss/` | [NSS patch internals](patches/nss-internals.md) |
| OpenSSL | `patches/openssl/BASE_REF` | `patches/openssl/` | [OpenSSL patch internals](patches/openssl-internals.md) |
| BoringSSL | `patches/boringssl/BASE_REF` | `patches/boringssl/` | [BoringSSL patch internals](patches/boringssl-internals.md) |

## Shared Runtime Knobs

All three stacks are expected to support:

- `tls_min` / `tls_max`,
- `strict`,
- `cipher_suites`,
- `cipher_mode` (`reorder`, `exact`),
- `alpn`,
- `signature_algorithms`,
- `extension_order`,
- `extension_mode` (`reorder`, `exact`),
- `sni_mode` (`present`, `domain`, `none`, `ip`),
- `enable_grease`,
- `enable_ch_xtn_permutation`,
- `supported_versions`,
- `supported_groups`,
- `key_share_groups`,
- `psk_key_exchange_modes`,
- `grease_value` where the stack supports explicit GREASE selection.

## Diagnostic Requirements

Every stack should write the schema-v1 dump described in
[JA4 Diagnostic Schema](ja4-diagnostic-schema.md):

- fixed `active`, `apply_ok`, `mismatch_mask` header,
- effective runtime knob block,
- complete `requested_*` block,
- complete `final_*` block,
- stable mismatch bits 0-12.

## Verification

Run the fixture harness:

```bash
scripts/ja4_verify.sh
```

For a full multi-stack run:

```bash
LIBS="openssl nss boringssl" FIXTURES="firefox-128 chrome-131 zen-1.x tor-13" \
  bash scripts/ja4_verify_all.sh verify
```

The harness validates:

- patch-applied runtime behavior,
- dump schema shape,
- requested/final parity,
- positive and negative fixtures,
- expected JA4 values when an observation endpoint is configured.

## Known Limits

| Stack | Notes |
|---|---|
| NSS | Browser runtime state still matters. Headless browser automation can fail before a TLS connection is attempted; the library path itself can be tested without a full browser process. |
| OpenSSL | Key-share regeneration and some extension-body rewrites are constrained by OpenSSL internals. CLI paths are useful for JA4 experiments but are not full browser emulation. |
| BoringSSL | Synthetic extension stubs can match JA4-visible IDs but do not implement semantic extension bodies. Full Chromium validation requires a local Chromium build. |

Keep this file concise. Detailed implementation notes belong in the
stack-specific internals documents.
