# NSS JA4 Patch Internals

This document gives reviewer-level orientation for the NSS patch stack.
User-facing runtime keys are documented in
[`docs/nss-ja4-config.md`](../nss-ja4-config.md).

## Patch Scope

The NSS patch adds:

- runtime config loading from `NSS_JA4_CONFIG`,
- ClientHello field overrides,
- exact and reorder modes for ciphers and extensions,
- TLS 1.3 extension body rewrites,
- key-share generation from requested groups,
- strict mismatch handling,
- schema-v1 diagnostic dumps through `NSS_JA4_DUMP`.

## Hook Flow

1. Load and parse the runtime config at ClientHello construction time.
2. Apply socket and cipher configuration before serialization.
3. Build the ClientHello through NSS' normal path.
4. Rewrite configured TLS 1.3 extension bodies where needed.
5. Reorder or exact-filter extensions according to `extension_order`.
6. Normalize `pre_shared_key` to the final extension position.
7. Re-parse the final extension buffer to collect `final_*`.
8. Compute `mismatch_mask`.
9. Write the dump and abort in strict mode when mismatches are present.

## Important Details

- `extension_mode=exact` can insert dependencies for body overrides.
- SNI is special because the body is required; the runtime uses `sni_mode`
  instead of emitting an empty SNI stub.
- `signature_schemes` is accepted as an alias for `signature_algorithms`.
- The dump schema is shared with BoringSSL and OpenSSL.

## Limits

- Browser process state can still affect Firefox handshakes.
- Headless browser startup issues are separate from the NSS hook.
- Exact mode can create protocol-invalid ClientHellos if required extensions are
  removed.

## Adding a New Knob

1. Extend the parser and config struct.
2. Add validation.
3. Apply the value in the relevant NSS ClientHello path.
4. Re-parse or note the final value.
5. Extend dump output in schema order.
6. Add fixture coverage.
