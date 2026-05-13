# tests/

This directory holds **shell-driven JA4 acceptance fixtures**, not Flutter
unit tests.

| Path | Purpose |
|---|---|
| `tests/ja4-fixtures/` | `.conf` profiles + matching `.expected` JA4 hashes used by `scripts/ja4_verify.sh` to confirm a patched TLS stack produces the right wire fingerprint. |
| `tests/ja4-fixtures/negative/` | Profiles that should be rejected by the parser. |

Each `*.conf` is a Fingerprint Config Standard (FCS) document; the matching
`*.expected` file is the JA4 hash that should be observed end-to-end.

Run them against a specific TLS library:

```bash
scripts/ja4_verify.sh --lib openssl --fixture chrome-131
scripts/ja4_verify.sh --lib nss     --fixture firefox-128
scripts/ja4_verify.sh --lib boringssl --fixture tor-13
```

Or run the full sweep:

```bash
scripts/ja4_verify_all.sh
```

## Flutter unit/widget tests live elsewhere

The Flutter desktop GUI's test suite is at
[`tools/ja4-spoofer/test/`](../tools/ja4-spoofer/test/) and runs via
`flutter test` (see `.github/workflows/ci.yml`). Don't confuse the two —
they are run by different harnesses.
