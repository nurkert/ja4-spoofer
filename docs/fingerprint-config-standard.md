# Fingerprint Config Standard

The Fingerprint Config Standard (FCS) is the shared profile format for
JA4-oriented TLS ClientHello configuration. It separates fingerprint intent from
stack-specific runtime switches.

## Structure

```yaml
schema_version: 1
profile_id: firefox-like-baseline
metadata:
  name: Firefox-like baseline
  author: you
  description: Reference profile for JA4 experiments

inputs:
  tls_client_hello:
    tls_min_version: 1.2
    tls_max_version: 1.3
    cipher_suites: [4865, 4866, 4867, 49195, 49199]
    alpn_protocols: [h2, http/1.1]

    extensions: [0, 10, 11, 13, 16, 43, 45, 51]
    supported_groups: [29, 23, 24]
    signature_algorithms: [1027, 2052, 1025, 1283]
    supported_versions: [772, 771]
    psk_key_exchange_modes: [1]
    key_share_groups: [29]
    sni_mode: domain

execution:
  nss:
    enable_grease: true
    enable_ch_xtn_permutation: false
```

## Field Rules

- `tls_min_version` and `tls_max_version` accept `1.0` to `1.3` or numeric TLS
  wire values (`769` to `772`).
- List fields are ordered arrays.
- `sni_mode` accepts `none`, `domain`, `ip` and `present`.
- `execution.<engine>` contains runtime switches for a specific stack.
- Unknown top-level fields should be ignored by readers and preserved by
  editors where possible.

## Mapping to Runtime Configs

The helper `scripts/fcs_emit.py` converts FCS profiles into stack-specific
runtime configs.

Direct NSS mapping:

| FCS field | Runtime key |
|---|---|
| `inputs.tls_client_hello.tls_min_version` | `tls_min` |
| `inputs.tls_client_hello.tls_max_version` | `tls_max` |
| `inputs.tls_client_hello.cipher_suites` | `cipher_suites` |
| `inputs.tls_client_hello.alpn_protocols` | `alpn` |
| `execution.nss.enable_grease` | `enable_grease` |
| `execution.nss.enable_ch_xtn_permutation` | `enable_ch_xtn_permutation` |

Fields that are valid in FCS but may not be emitted by every stack-specific
backend:

- `extensions`
- `supported_groups`
- `signature_algorithms`
- `supported_versions`
- `psk_key_exchange_modes`
- `key_share_groups`
- `sni_mode`

The format is intentionally broader than any single current backend so profiles
can survive future stack support without schema churn.
