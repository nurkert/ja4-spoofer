# Impersonation Edge Cases

This document lists cases where a profile can match JA4 but still differ from a
real client or behave inconsistently.

## JA4 Equality Is Not Wire Equality

A matching JA4 hash means the JA4-relevant fields match. It does not guarantee:

- identical ClientHello bytes,
- identical extension bodies,
- identical session state,
- identical browser runtime behavior,
- identical network or HTTP behavior.

For strict comparisons, inspect the effective dump and a packet capture in
addition to the JA4 hash.

## OpenSSL Caveats

OpenSSL is excellent for scriptable experiments, but it is not a browser TLS
stack.

Known caveats:

- Some browser-specific byte-level behaviors do not exist naturally in OpenSSL.
- Internal validation can filter unsupported groups, ciphers or protocol ranges.
- Certain extensions depend on other extensions or runtime state.
- GREASE creates intentional run-to-run variation when enabled.
- PSK, session tickets and resumption can change later handshakes.
- ECH and experimental extensions are build- and stack-dependent.

Typical symptom: requested values appear in the input config but are absent or
different in `final_*` dump fields.

## Browser / NSS Caveats

Browser launches have additional runtime state:

- existing browser processes,
- profile directories,
- preferences and policies,
- session caches,
- extension and feature flags.

For reproducible measurements, use a clean profile directory, terminate old
processes before launch, and compare first connections separately from resumed
connections.

## Measurement Caveats

Measurement targets can vary independently:

- CDN routing,
- TLS terminator deployments,
- redirects,
- HTTP/2 vs HTTP/1.1 paths,
- DNS and proxy configuration,
- captive portals or local security software.

Always compare like with like: same URL, same DNS path, same proxy state, same
browser profile state and same process lifecycle.

## Troubleshooting

| Symptom | Check |
|---|---|
| JA4 matches but server behavior differs | Compare PCAP and effective dump, not just JA4 |
| Handshake error in `exact` mode | Check extension dependencies, groups and final dump |
| Results change between runs | Check GREASE, resumption, cache and existing processes |
| GUI profile seems ignored | Confirm the patched binary was launched and rebuild if needed |

## Reproducibility Checklist

1. Use freshly built patched binaries.
2. Stop existing browser and curl processes before measuring.
3. Use an isolated browser profile directory.
4. Compare first-run and resumed handshakes separately.
5. Check `requested_*` against `final_*`.
6. Capture packets when byte-level fidelity matters.
7. Evaluate GREASE both enabled and disabled when it is relevant.
