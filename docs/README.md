# Documentation

This directory contains the technical documentation for JA4 Spoofer.

## Start Here

- [Managed libraries and patch workflow](managed-libs.md)
- [Advanced launch options](advanced-launch.md)
- [Fingerprint Config Standard](fingerprint-config-standard.md)
- [JA4 capabilities and limits](ja4-spoofing-summary.md)
- [Impersonation edge cases](impersonation-edge-cases.md)

## Runtime Configuration

- [BoringSSL JA4 runtime hook](boringssl-ja4-config.md)
- [NSS JA4 runtime hook](nss-ja4-config.md)
- [OpenSSL JA4 runtime hook](openssl-ja4-config.md)
- [JA4 diagnostic schema](ja4-diagnostic-schema.md)

## Background

- [JA4 extension-content analysis](ja4.md)
- [TLS ClientHello and cipher-suite order](tls.md)
- [Library fingerprints vs application fingerprints](lib-vs-app-fingerprint.md)
- [GREASE and replay policy](grease.md)
- [TLS library landscape](ssllibs.md)

## GUI and Extensibility

- [Add a new tool to the GUI](add-new-tool.md)
- [Randomizer architecture](randomizer-architecture.md)
- [Historical randomizer evaluation](randomizer-research-results.md)

## Patch Internals

- [BoringSSL patch internals](patches/boringssl-internals.md)
- [NSS patch internals](patches/nss-internals.md)
- [OpenSSL patch internals](patches/openssl-internals.md)

## Datasets

The files in `docs/datasets/` are captured evaluation artifacts. They are kept
as historical data, not as current compatibility guarantees.
