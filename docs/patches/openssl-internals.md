# OpenSSL JA4 Patch Internals

This document gives reviewer-level orientation for the OpenSSL patch stack.
User-facing runtime keys are documented in
[`docs/openssl-ja4-config.md`](../openssl-ja4-config.md).

## Patch Scope

The OpenSSL patch stack adds:

- runtime config loading from `OPENSSL_JA4_CONFIG`,
- a JA4 state and helper implementation in `ssl/ja4.c`,
- cipher-list exact emission,
- extension reorder and exact modes,
- selected TLS 1.3 extension body rewrites,
- deterministic extension permutation,
- schema-v1 diagnostic dumps through `OPENSSL_JA4_DUMP`.

## Hook Flow

1. Reset and parse JA4 state before ClientHello construction.
2. Expose override providers for OpenSSL extension builders.
3. Apply cipher, ALPN, SNI, signature algorithm and TLS 1.3 field overrides.
4. Reorder built-in ClientHello extensions.
5. Rewrite supported same-size extension bodies after serialization where
   required.
6. Validate `requested_*` against `final_*`.
7. Write the dump and abort in strict mode when mismatches are present.

## Important Details

- `cipher_mode=exact` writes requested 16-bit cipher IDs directly, including
  IDs OpenSSL does not know as `SSL_CIPHER` objects.
- OpenSSL still enforces internal consistency for many cryptographic paths.
- Some extension body rewrites are constrained by serialized size.
- The CLI path is useful for JA4 experiments, but it is not browser emulation.

## Limits

- Key-share regeneration is limited by OpenSSL internals.
- Custom extensions outside the built-in extension block may not be reordered in
  the same way.
- HelloRetryRequest and resumption paths need separate validation.
- Exact mode can intentionally create protocol-invalid ClientHellos.

## Adding a New Knob

1. Extend `ssl/ja4.c` parsing and config state.
2. Add validation and mismatch behavior.
3. Hook into the relevant OpenSSL builder or wire-rewrite path.
4. Capture the final value.
5. Extend dump output in schema order.
6. Add fixture coverage.
