# Library Fingerprints vs Application Fingerprints

A TLS library does not determine a JA4 fingerprint by itself. The application
using the library also controls configuration, feature flags, ALPN, extension
selection and runtime state.

## Why This Matters

Two applications can use the same TLS stack and still produce different
ClientHellos. Conversely, a patched stack can often reproduce the JA4-relevant
shape of a different application when the relevant fields are configurable.

Examples:

- Chrome and other Chromium-based clients use BoringSSL but can differ through
  feature flags, ALPN, GREASE, ECH, extension order and build configuration.
- Firefox uses NSS, but profile state and preferences can affect handshakes.
- curl with OpenSSL is easy to script, but it is not a browser and does not
  naturally produce all browser-specific behaviors.

## What JA4 Spoofer Controls

JA4 Spoofer focuses on the ClientHello fields that influence JA4:

- cipher-suite IDs,
- extension IDs and order,
- signature algorithms,
- supported versions,
- supported groups,
- key shares,
- PSK modes,
- SNI mode,
- ALPN,
- GREASE and extension permutation switches.

## What Remains Application-Specific

Some behavior remains outside a generic library patch:

- extension body details,
- feature negotiation tied to browser runtime state,
- profile and policy settings,
- session tickets and resumption,
- ECH availability,
- HTTP stack behavior after TLS completes.

## Practical Guidance

When building a profile, prefer captures from the exact client version you want
to study. Use library defaults as a starting point, not as proof that a profile
matches an application.

For validation:

1. Compare the effective dump against the requested profile.
2. Compare observed JA4 against the expected JA4.
3. Use packet captures for byte-level claims.
4. Re-test when the upstream browser or TLS library changes.
