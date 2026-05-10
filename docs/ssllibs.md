# TLS Library Landscape

JA4 Spoofer currently focuses on BoringSSL, NSS and OpenSSL because they cover a
large share of browser and command-line TLS behavior.

## Supported Stacks

| Stack | Common users | Why it matters here |
|---|---|---|
| BoringSSL | Chromium-based browsers and Android components | Represents the dominant Chromium-style ClientHello family |
| NSS | Firefox and Mozilla tooling | Represents an independent browser TLS stack |
| OpenSSL | curl, servers, scripting environments and many native tools | Provides a fast and scriptable CLI experimentation path |

## Other Important Stacks

| Stack | Typical environment |
|---|---|
| Secure Transport / Network.framework | Apple platform clients |
| SChannel | Windows native clients |
| JSSE | Java applications |
| Go `crypto/tls` | Go services and tools |
| GnuTLS | GNU/Linux tools and applications |
| rustls | Rust applications and services |
| mbed TLS / wolfSSL | Embedded and IoT systems |

## Interpretation

Stack choice is only one input to a ClientHello fingerprint. The application,
build flags, runtime profile, feature gates and network state also matter. See
[Library Fingerprints vs Application Fingerprints](lib-vs-app-fingerprint.md)
for details.
