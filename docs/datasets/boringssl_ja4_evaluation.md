# BoringSSL bssl JA4 Practical Evaluation

- Binary: `/Users/nurkert/build/boringssl-ja4-standalone/bssl`
- Endpoint: `ja4-observer.example:443`
- Cases: `12`
- Baseline JA4 (live): `t13d171000_5b57614c22b0_78e6aca7449b`
- Baseline JA4 (local): `t13d171000_5b57614c22b0_78e6aca7449b`

## Kurzfazit

- Erfolgreiche Verbindungen: `7/12`
- Exaktes Replay des Default-Fingerprints: `0` Fall/Fälle
- Gezieltes erfolgreiches Spoofing auf andere JA4s: `2` Fälle
- Kein sichtbarer Effekt: `4` Fälle

JA4 wird lokal aus den Wire-Level-Feldern im BORINGSSL_JA4_DUMP berechnet. Cipher, Extension-Reihenfolge und Sigalgs kommen direkt aus dem serialisierten ClientHello — das Ergebnis ist damit äquivalent zu einem Server-seitigen JA4-Echo.

## Ergebnisübersicht

| Fall | Typ | JA4 (live) | JA4 (lokal) | Delta vs. Baseline | apply_ok | Einordnung |
|---|---|---|---|---:|---|---|
| baseline-default | Baseline | `t13d171000_5b57614c22b0_78e6aca7449b` | `t13d171000_5b57614c22b0_78e6aca7449b` | 0 | ok (mask=0) | Referenz |
| replay-baseline-exact | Replay | `` | `` | 3 | — | Fehlgeschlagen |
| exact-compact-tls13 | Gezielt exakt | `t13d0309h2_55b375c5d22e_0a6e5608a8a8` | `t13d0309h2_55b375c5d22e_0a6e5608a8a8` | 3 | ok (mask=0) | Hoch: gezieltes Spoofing |
| exact-http1-tls12only | Gezielt exakt | `` | `` | 3 | — | Fehlgeschlagen |
| reorder-cipher-prefix | Gezielt Reorder | `t13d171000_5b57614c22b0_78e6aca7449b` | `t13d171000_5b57614c22b0_78e6aca7449b` | 0 | ok (mask=0) | Niedrig/kein sichtbarer Effekt |
| reorder-ext-prefix | Gezielt Reorder | `t13d171000_5b57614c22b0_78e6aca7449b` | `t13d171000_5b57614c22b0_78e6aca7449b` | 0 | ok (mask=0) | Niedrig/kein sichtbarer Effekt |
| grease-on-fixed-3a3a | Gezielt exakt | `t13d171100_5b57614c22b0_ef7df7f74e48` | `t13d171100_5b57614c22b0_ef7df7f74e48` | 2 | ok (mask=0) | Hoch: gezieltes Spoofing |
| grease-off-no-permute | Gezielt exakt | `t13d171000_5b57614c22b0_78e6aca7449b` | `t13d171000_5b57614c22b0_78e6aca7449b` | 0 | ok (mask=0) | Niedrig/kein sichtbarer Effekt |
| exact-chromium-like | Gezielt exakt | `` | `` | 3 | — | Fehlgeschlagen |
| sni-suppressed | Gezielt exakt | `` | `t13i170900_5b57614c22b0_78e6aca7449b` | 1 | — | Fehlgeschlagen |
| alt-sigalgs-sha384-only | Gezielt exakt | `` | `t13d171000_5b57614c22b0_ce5e2d9bed52` | 1 | — | Fehlgeschlagen |
| psk-modes-both | Gezielt exakt | `t13d171000_5b57614c22b0_78e6aca7449b` | `t13d171000_5b57614c22b0_78e6aca7449b` | 0 | ok (mask=0) | Niedrig/kein sichtbarer Effekt |

## Bewertungslegende

- **Sehr hoch: exaktes Replay** — Baseline-Fingerprint exakt reproduziert.
- **Hoch: gezieltes Spoofing** — Deutlich anderer JA4 kontrolliert erzeugt (≥2 Segmente).
- **Mittel: partielles Spoofing** — Ein Segment geändert.
- **Mittel: Reorder-Steuerung** — Reihenfolge sichtbar geändert.
- **Niedrig/kein sichtbarer Effekt** — JA4 identisch zur Baseline.
- **Teilweise** — apply_ok=0 oder mismatch_mask≠0 (Config nicht vollständig anwendbar).
- **Fehlgeschlagen** — Verbindung oder Dump fehlgeschlagen.

## Methodische Hinweise

- JA4 wird aus `BORINGSSL_JA4_DUMP` (`final_cipher_suites`, `final_extension_order`,
  `final_signature_algorithms`, `final_supported_versions`) lokal berechnet.
- GREASE-Werte (0x0a0a–0xfafa) werden vor der JA4-Berechnung herausgefiltert.
- `final_*`-Felder spiegeln die tatsächlich im ClientHello gesendeten Wire-Bytes wider.
- Kein Browser, kein Selenium, kein externer JA4-Echo-Endpoint nötig.

Die autoritativen Rohdaten liegen direkt daneben als JSON und CSV.
