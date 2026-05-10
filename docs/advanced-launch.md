# Advanced Launch Options

The GUI intentionally keeps the launch flow compact: choose a profile, choose a
client, launch. Lower-level controls such as custom target URLs, `--dump`,
`--show-config`, `--dry-run`, process handling and raw browser arguments are
available through the scripts.

## Run Scripts

| Client | Script |
|---|---|
| Firefox | `scripts/run_firefox_with_ja4.sh` |
| Chromium / Brave-style builds | `scripts/run_chromium_with_ja4.sh` |
| curl | `scripts/run_curl_with_ja4.sh` |
| BoringSSL smoke test | `scripts/run_boringssl_with_ja4.sh` |

All scripts share the parser in `scripts/lib/parse_ja4_args.sh`. Most flags are
consistent across clients; a client may silently ignore flags that do not apply
to its runtime.

## TLS Payload Flags

| Flag | Meaning |
|---|---|
| `--tls-min <ver>` / `--tls-max <ver>` | Minimum and maximum TLS version. Accepts `1.2`, `1.3`, `771`, `772`. |
| `--cipher-suites <csv>` | Ordered cipher-suite list. |
| `--cipher-mode <reorder\|exact>` | `exact` writes the requested list to the wire; `reorder` only reorders known values. |
| `--extension-order <csv>` | Ordered extension ID list. |
| `--extension-mode <reorder\|exact>` | Same semantics as `--cipher-mode`. |
| `--alpn <csv>` | ALPN protocols, for example `h2,http/1.1`. |
| `--signature-algorithms <csv>` | Signature algorithm IDs. |
| `--supported-versions <csv>` | TLS `supported_versions` list. |
| `--supported-groups <csv>` | Named group IDs. |
| `--key-share-groups <csv>` | TLS 1.3 key-share groups. |
| `--psk-key-exchange-modes <csv>` | PSK key exchange modes. |
| `--sni-mode <present\|domain\|none\|ip>` | SNI behavior. |
| `--enable-grease <0\|1>` | Inject RFC 8701 GREASE values. Captured profiles are coerced to `0` by the GUI. |
| `--enable-ch-xtn-permutation <0\|1>` | Enable ClientHello extension permutation where supported. |
| `--strict <0\|1>` | Abort on mismatches instead of falling back to best effort. |

## Launch Wrapper Flags

| Flag | Meaning |
|---|---|
| `--config <path>` | Base config file to merge with CLI flags. |
| `--config-out <path>` | Path for the effective runtime config. |
| `--dump <path>` | Write the effective values sent by the TLS stack. |
| `--no-dump` | Disable runtime dump generation. |
| `--profile-dir <path>` | Browser profile or user-data directory. |
| `--browser-bin <path>` | Override browser binary path. |
| `--show-config` | Print the effective config before launch. |
| `--dry-run` | Print environment and command without starting the client. |
| `--allow-existing` | Allow an already running browser instance. |
| `--kill-existing` | Terminate existing browser instances before launch. |
| `--set key=value` | Raw config override; can be passed multiple times. |

Everything after the first `--` is forwarded to the client:

```bash
scripts/run_firefox_with_ja4.sh --tls-min 1.2 -- https://example.com
```

## Examples

Firefox with an exact replay profile:

```bash
scripts/run_firefox_with_ja4.sh \
  --tls-min 1.2 --tls-max 1.3 \
  --cipher-suites 4865,4867,4866,49195,49199,52393,52392 \
  --cipher-mode exact \
  --extension-order 0,23,65281,10,11,35,16,5,34,18,51,43,13,45,28,27 \
  --extension-mode exact \
  --alpn h2,http/1.1 \
  --enable-grease 0 \
  --kill-existing \
  --show-config \
  -- https://example.com
```

curl with a minimal TLS 1.3 cipher list and a diagnostic dump:

```bash
scripts/run_curl_with_ja4.sh \
  --tls-min 1.3 --tls-max 1.3 \
  --cipher-suites 4865 \
  --dump /tmp/curl-ja4-dump.conf \
  -- https://example.com
```

Chromium dry run:

```bash
scripts/run_chromium_with_ja4.sh \
  --tls-min 1.2 --tls-max 1.3 \
  --cipher-suites 4865,4866,4867,49195,49196,49199,49200 \
  --cipher-mode exact \
  --dry-run
```

## Loading GUI Profiles

Saved GUI profiles live in:

```text
~/.ja4-spoofer/profiles/<id>.json
```

The launch scripts use INI-style runtime configs, so the easiest way to reuse a
GUI profile from the command line is to launch once with `--show-config` or a
custom `--config-out`, then reuse that generated config file.

## Chromium Sandbox Note

The Chromium launcher adds `--no-sandbox` for local unsigned developer builds.
Without a correctly signed app bundle and helper bundle layout, Chromium's
renderer sandbox can fail at startup on macOS.

Chromium shows its own warning banner for that flag. If you are launching a
properly signed build and want to remove the flag, edit
`scripts/browsers/chromium.sh` and remove `--no-sandbox` from
`BROWSER_EXTRA_DEFAULT_ARGS`.
