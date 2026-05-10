# JA4 Extension-Content Analysis

This note explains which ClientHello fields affect JA4 and why extension bodies
usually do not affect the hashed extension component.

## Short Answer

For the extension hash component (`JA4_c`), JA4 uses extension IDs and signature
algorithm IDs. It does not hash the bytes inside most extension bodies.

Extension contents can still matter for the readable shape component (`JA4_a`).
For example, the TLS version is commonly inferred from the `supported_versions`
extension body.

## JA4 Structure

An example JA4 fingerprint:

```text
t13d1516h2_8daaf6152771_d8a2da3f94cd
```

![JA4 structure](../assets/ja4_structure.png)

The three components are:

| Component | Meaning |
|---|---|
| `JA4_a` | Human-readable ClientHello shape: transport, TLS version, SNI class, counts and ALPN |
| `JA4_b` | Truncated hash of normalized cipher-suite IDs |
| `JA4_c` | Truncated hash of normalized extension IDs plus signature algorithms |

## Extension IDs vs Extension Bodies

For `JA4_c`, the relevant input is the list of extension IDs such as `0x0000`
for SNI or `0x002b` for `supported_versions`. The body of `supported_versions`
may contain `TLS 1.3` and `TLS 1.2`, but that body is not part of the extension
ID list used for the `JA4_c` hash.

This means:

- changing an extension body can leave `JA4_c` unchanged,
- adding or removing the extension ID changes `JA4_c`,
- changing signature algorithm IDs can also change `JA4_c`.

## Where Extension Bodies Still Matter

Extension contents can affect other parts of the fingerprint or the handshake:

- `supported_versions` influences the TLS version reported in `JA4_a`,
- ALPN affects the ALPN marker in `JA4_a`,
- invalid extension bodies can break the TLS handshake,
- non-JA4 tools may compare full ClientHello bytes and detect body differences.

## Implication for JA4 Spoofer

JA4 Spoofer focuses on the fields JA4 actually uses:

- cipher-suite IDs,
- extension ID order and set,
- signature algorithm IDs,
- version, ALPN, SNI and count-affecting fields.

It does not try to make every extension body byte-identical across unrelated TLS
libraries. Byte-level replay beyond JA4 should be validated with packet captures
and stack-specific dumps.
