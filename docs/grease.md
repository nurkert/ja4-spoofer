# GREASE and Replay Policy

GREASE means **Generate Random Extensions And Sustain Extensibility**. TLS
clients intentionally send reserved values so servers, proxies and middleboxes
learn to ignore unknown values instead of ossifying around today's known set.

GREASE is not a privacy feature by itself. It is a protocol-extensibility
mechanism.

## Where GREASE Appears

TLS can carry GREASE values in several offer lists:

- cipher suites,
- extensions,
- supported versions,
- supported groups,
- key shares,
- other extension-specific vectors.

RFC 8701 defines the reserved GREASE codepoint pattern. RFC 9170 describes the
same long-term extensibility idea more generally.

## JA4 Stability

JA4 removes GREASE values before sorting and hashing cipher suites, extensions
and signature algorithms. A standards-compliant JA4 implementation should
therefore produce the same JA4 hash for two otherwise identical ClientHellos
that differ only in GREASE codepoints.

Practical implication:

- GREASE should not change `JA4_b`.
- GREASE should not change `JA4_c`.
- If a measured JA4 hash changes only because GREASE changed, the measuring
  implementation is likely not applying the JA4 GREASE filter consistently.

## Why Captured Profiles Disable GREASE

Captured profiles are meant to replay the observed ClientHello shape as closely
as possible. The capture pipeline stores the normalized JA4-relevant lists
without GREASE values. Re-injecting GREASE during replay would add values that
were not present in the captured normalized profile.

That has four unwanted effects:

1. The wire bytes no longer match the captured ClientHello.
2. Non-JA4 tools can see count or byte-level drift.
3. Some non-reference JA4 implementations mishandle GREASE in signature
   algorithm lists.
4. Diagnostic comparisons such as `requested_cipher_suites` vs
   `final_cipher_suites` can report mismatches even when the JA4 hash still
   matches.

For that reason, the launcher coerces profiles with `metadata.source ==
"captured"` to:

```text
enable_grease=0
enable_ch_xtn_permutation=0
```

The implementation lives in:

```text
tools/ja4-spoofer/lib/core/utils/profile_args.dart
```

Manually created profiles keep the explicit GREASE flag selected by the user.

## Practical Rule

| Profile type | `enable_grease` | Reason |
|---|---|---|
| Captured replay | Forced `0` | Preserve reproducible replay and diagnostics |
| Manual profile, deterministic output | `0` | Avoid run-to-run wire drift |
| Manual profile, browser-like live behavior | `1` | Closer to Chromium/Brave-style behavior |

In short: GREASE is good protocol hygiene, but it is usually the wrong default
for exact captured replay.

## References

- RFC 8701: Applying GREASE to TLS Extensibility
- RFC 8446: TLS 1.3
- RFC 9170: Long-Term Viability of Protocol Extension Mechanisms
- FoxIO JA4 technical details
