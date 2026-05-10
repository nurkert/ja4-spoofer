# Historical Randomizer Evaluation

This document preserves the original randomizer evaluation as historical
engineering context. It is not a promise that the same endpoints, binaries or
network conditions still produce identical results.

## Test Setup

The evaluation generated random curl/OpenSSL profiles and compared:

- local profile mutations,
- the observed JA4 hash from a JA4 echo endpoint,
- compatibility against common HTTPS endpoints.

The curl/OpenSSL path was used because it is fast to rebuild and easy to run in
large batches.

## Main Findings

| Mode | Observed behavior |
|---|---|
| `constrained + permute` | Very reliable. Mostly changes wire order, not sorted JA4 hash components. |
| `mixed + swap` | Produces useful `JA4_b` / `JA4_c` drift while remaining broadly compatible. |
| `drop` / `appendJunk` | Changes counts and therefore can change `JA4_a`; compatibility depends on what was removed or added. |
| `chaos` | Produces maximum drift but many real servers reject or fail the handshake. |

## Practical Recommendations

- Start with `mixed` pool and `permute + swap`.
- Keep safety pins enabled for normal usage.
- Enable count-changing mutations only when `JA4_a` drift is intentional.
- Treat compatibility probes as hints, not proof. Validate important profiles
  against the exact systems you care about.

## Reproducibility Notes

Randomizer output is deterministic for a fixed app, settings set and master
seed. Compatibility is not fully deterministic because remote TLS endpoints,
network routing, certificate state and server deployments change over time.

For current behavior, rerun the randomizer and inspect the effective dump files
instead of relying on this historical snapshot.
