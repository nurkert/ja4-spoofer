# Randomizer Architecture

The GUI contains a per-app randomizer that generates fresh ClientHello profiles
from each app's own TLS defaults. It reuses the same launch and patch pipeline
as captured replay; there is no separate TLS code path for randomized profiles.

## Goals

The randomizer is designed to answer three practical questions:

1. How much can a profile change before its JA4 hash changes?
2. Which mutations still produce successful TLS handshakes on common servers?
3. Can the same randomization model work across BoringSSL, NSS and OpenSSL?

## Launch Path

```text
Roll button
  -> RandomEngine.roll(app, config, masterSeed)
  -> FingerprintProfile
  -> profile_args.dart
  -> run_<app>_with_ja4.sh
  -> patched TLS stack
```

When compatibility probing is enabled, the GUI also runs HEAD probes against a
small set of stable public endpoints and displays a compatibility badge.

## Source of Truth

The Quick Launch screen has three mutually exclusive profile sources:

| Source | Launch input |
|---|---|
| Profile | Saved or captured profile |
| TLS Configuration | Live configurator state |
| Randomize | In-memory per-app roll |

Only the active section is used for launch. Clicking **Roll** updates the random
state; selecting the Randomize section makes that state the launch source.

## Pool and Mutation Model

Each component has two independent axes.

### Pools

| Pool | Source | Tradeoff |
|---|---|---|
| `constrained` | IDs already present in the app defaults | Safest, limited drift |
| `mixed` | App defaults plus public TLS registry values | Useful drift, usually compatible |
| `chaos` | Arbitrary 16-bit values | Maximum drift, many failures expected |

### Mutations

| Mutation | Effect |
|---|---|
| `permute` | Shuffle order without changing IDs |
| `drop` | Remove non-pinned IDs |
| `swap` | Replace IDs with alternatives from the pool |
| `appendJunk` | Append extra IDs |

Count-changing mutations (`drop`, `appendJunk`) can change `JA4_a`. Swapping IDs
can change `JA4_b` or `JA4_c`. Permuting order changes wire order but not sorted
JA4 hash components.

## Safety Pins

By default the randomizer keeps TLS-critical values in place, including common
TLS 1.3 cipher suites, supported groups, signature algorithms, supported
versions, PSK modes and key shares. Relaxing those pins produces more extreme
profiles but makes handshake failures much more likely.

## Seeds

Every roll uses a master seed. The engine derives a per-app sub-seed with:

```text
SHA256(masterSeed + appId).first8bytes
```

That gives reproducible profiles per app while keeping different apps
independent from one another.

## Move to Configurator

Random profiles are in-memory by default. To persist one:

1. Activate the Randomize section.
2. Click the move action on an app tile.
3. The configurator is filled with the rolled values.
4. Edit if needed and save through the normal profile workflow.

This avoids a second save path for random profiles.

## Compatibility Probes

The compatibility prober uses a small hardcoded endpoint set:

```dart
const defaultProbeEndpoints = [
  'https://www.google.com',
  'https://www.cloudflare.com',
  'https://example.com',
];
```

Probe results are advisory. Network errors, captive portals, DNS overrides or
local firewalls can make results inconclusive even when the generated profile is
valid.

## Relevant Code

| Area | Path |
|---|---|
| Random engine | `tools/ja4-spoofer/lib/core/utils/random_engine.dart` |
| Profile-to-args bridge | `tools/ja4-spoofer/lib/core/utils/profile_args.dart` |
| Compatibility probe | `tools/ja4-spoofer/lib/core/utils/compat_prober.dart` |
| Quick Launch controller | `tools/ja4-spoofer/lib/features/quick_launch/quick_launch_controller.dart` |
| Randomizer UI | `tools/ja4-spoofer/lib/features/quick_launch/widgets/randomize_options_card.dart` |
| Configurator bridge | `tools/ja4-spoofer/lib/features/configurator/configurator_controller.dart` |
