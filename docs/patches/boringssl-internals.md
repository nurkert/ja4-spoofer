# BoringSSL JA4 Patch Internals

This document gives reviewer-level orientation for the BoringSSL patch stack.
User-facing runtime keys are documented in
[`docs/boringssl-ja4-config.md`](../boringssl-ja4-config.md).

## Patch Scope

The BoringSSL patch stack adds:

- runtime config parsing,
- strict validation,
- cipher and extension replay modes,
- dependency closure for JA4-relevant extensions,
- synthetic extension stubs for exact-mode unknown IDs,
- diagnostic dump output following schema v1.

## Runtime State

JA4 state is attached to the per-handshake state, not global process state. That
keeps concurrent connections isolated.

Core concepts:

- `ssl_ja4_mode_t`: `none`, `reorder`, `exact`
- `ssl_ja4_config_t`: parsed runtime config
- `ssl_ja4_mismatch_bits_t`: schema-v1 mismatch bits
- `requested_*`: values from config
- `final_*`: values reconstructed from the serialized ClientHello

## Hook Flow

1. Parse `BORINGSSL_JA4_CONFIG` before ClientHello construction.
2. Validate config and set mismatch bits.
3. Apply TLS version, cipher, extension, SNI, ALPN and GREASE overrides through
   BoringSSL's existing ClientHello builders.
4. Force-emit requested built-in extensions when exact replay requires them.
5. Emit zero-length synthetic stubs for exact-mode unknown extension IDs.
6. Re-parse the serialized ClientHello and fill `final_*`.
7. Write `BORINGSSL_JA4_DUMP` if configured.
8. Abort if `strict=1` and `mismatch_mask != 0`.

## Limits

- Synthetic extension stubs match JA4-visible IDs but do not provide semantic
  extension bodies.
- Unsupported key-share groups cannot be made cryptographically valid by a
  synthetic ID alone.
- Exact mode can intentionally create protocol-invalid ClientHellos.
- Full browser validation still requires a local Chromium build; the BoringSSL
  CLI path is the faster stack-level verification path.

## Adding a New Knob

1. Add parser support.
2. Add validation and mismatch behavior.
3. Apply the override in the relevant ClientHello builder.
4. Capture the final on-wire value.
5. Extend the dump while preserving schema order.
6. Add positive and negative fixtures.
