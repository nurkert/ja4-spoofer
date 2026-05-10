# JA4 Capabilities and Limits

This page summarizes what JA4 Spoofer can and cannot control across the patched
BoringSSL, NSS and OpenSSL paths.

## Current Capability

JA4 Spoofer can deterministically control the JA4-relevant parts of the
ClientHello for the supported clients:

- Chromium / Brave-style builds through patched BoringSSL,
- Firefox through patched NSS,
- curl and OpenSSL CLI paths through patched OpenSSL.

The runtime hooks expose controls for:

- cipher suites and cipher mode (`reorder` or `exact`),
- extension order and extension mode (`reorder` or `exact`),
- signature algorithms,
- supported versions,
- supported groups,
- key-share groups,
- PSK key exchange modes,
- ALPN,
- SNI mode,
- GREASE,
- ClientHello extension permutation,
- TLS min/max version,
- strict mismatch handling.

In `exact` mode, the patch stacks can emit raw cipher and extension IDs that are
not present in the TLS library's normal built-in tables. This makes JA4 hash
experiments possible even for unusual or vendor-specific IDs.

## What This Does Not Mean

Matching a JA4 hash is not the same thing as perfectly matching every byte of a
ClientHello or perfectly emulating a browser.

JA4 does not cover:

- every extension body,
- session resumption state,
- all ECH/PSK behavior,
- TCP/IP behavior,
- HTTP behavior,
- JavaScript/browser runtime characteristics,
- server-side signals outside the ClientHello.

Use JA4 equality as a fingerprinting result, not as proof of total client
identity.

## Stack Notes

| Stack | Strengths | Remaining caveats |
|---|---|---|
| BoringSSL | Good fit for Chromium-style ClientHello experiments | Real browser behavior still depends on Chromium runtime state |
| NSS | Good fit for Firefox replay and profile-driven experiments | Browser profile state, prefs and session cache can affect handshakes |
| OpenSSL | Useful for scriptable curl/CLI experiments | Some byte-level browser behaviors are not natural OpenSSL behaviors |

## Diagnostics

Each stack can write an effective runtime dump with:

- `requested_*` fields from the profile/config,
- `final_*` fields reconstructed from the emitted ClientHello,
- `mismatch_mask`,
- `apply_ok`.

The shared dump schema is documented in
[JA4 Diagnostic Schema](ja4-diagnostic-schema.md).

For robust verification, compare:

1. the requested profile,
2. the effective dump,
3. the observed JA4 hash,
4. a packet capture when byte-level replay matters.

## Verification Harness

The fixture-driven harness lives in:

```bash
scripts/ja4_verify.sh
```

Fixtures live under:

```text
tests/ja4-fixtures/
```

The harness checks schema shape, requested/final parity, mismatch bits and
expected JA4 values where available.
