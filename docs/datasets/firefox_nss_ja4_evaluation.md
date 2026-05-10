# Firefox NSS JA4 Practical Evaluation

- Binary: `/Users/nurkert/build/firefox-ja4-stable/gecko-dev/obj-ja4-stable/dist/Nightly.app/Contents/MacOS/firefox`
- Endpoint: `https://ja4-observer.example/raw`
- Cases: `13`
- Baseline JA4: `t13d1514h2_8daaf6152771_4e21baae1cb2`

## Kurzfazit

- Erfolgreiche Live-Laeufe: `12/13`
- Exaktes Replay des aktuellen Default-Fingerprints: `1` Fall
- Klar erfolgreiches gezieltes Spoofing auf andere JA4s: `2` Faelle
- Sichtbare Randomisierung: `4` Faelle
- Geringer oder kein sichtbarer Effekt: `3` Faelle

Die Messung zeigt klar: exaktes Replay und gezielte starke Profilwechsel funktionieren gut. Die eingebaute Randomisierung veraendert in diesem Setup meist nur den Hash-/Body-Teil des JA4, nicht automatisch die komplette aeussere Shape.

## Ergebnisuebersicht

| Fall | Typ | Beobachteter JA4 | Delta vs. Baseline | Laufzeitstatus | Einordnung |
|---|---|---|---:|---|---|
| baseline-default | Baseline | `t13d1514h2_8daaf6152771_4e21baae1cb2` | 0 | ok, apply_ok=1 | Referenz |
| replay-current-exact | Replay | `t13d1514h2_8daaf6152771_4e21baae1cb2` | 0 | ok, apply_ok=1 | Sehr hoch: exaktes Replay |
| reorder-prefix-http-fields | Gezielt Reorder | `t13d1514h2_8daaf6152771_4e21baae1cb2` | 0 | ok, apply_ok=1 | Niedrig/kein sichtbarer Effekt |
| exact-http1-compact | Gezielt exakt | `t13d0514h1_e133e205ac38_8c1508522488` | 3 | ok, apply_ok=1 | Hoch: gezieltes Spoofing |
| exact-tls12-http1 | Gezielt exakt | `t12d1210h1_d34a8e72043a_f044b497c07a` | 3 | ok, apply_ok=1 | Hoch: gezieltes Spoofing |
| exact-h2-only | Gezielt exakt | `` | 3 | request failed, apply_ok=1 | Fehlgeschlagen |
| exact-alt-groups | Gezielt exakt | `t13d1514h2_8daaf6152771_4e21baae1cb2` | 0 | ok, apply_ok=1 | Niedrig/kein sichtbarer Effekt |
| exact-alt-signatures | Gezielt exakt | `t13d1514h2_8daaf6152771_33394705ba66` | 1 | ok, apply_ok=1 | Mittel: partielles Spoofing |
| random-grease-only | Randomisiert | `t13d1514h2_8daaf6152771_2a4d78a5e06f` | 1 | ok, apply_ok=1 | Mittel: Hash-Randomisierung |
| random-permute-only | Randomisiert | `t13d1514h2_8daaf6152771_4e21baae1cb2` | 0 | ok, apply_ok=1 | Niedrig/kein sichtbarer Effekt |
| random-both-run-1 | Randomisiert | `t13d1514h2_8daaf6152771_c1f9a83a722b` | 1 | ok, apply_ok=1 | Mittel: Hash-Randomisierung |
| random-both-run-2 | Randomisiert | `t13d1514h2_8daaf6152771_da34bdbc8551` | 1 | ok, apply_ok=1 | Mittel: Hash-Randomisierung |
| random-both-run-3 | Randomisiert | `t13d1514h2_8daaf6152771_3c613bc8d462` | 1 | ok, apply_ok=1 | Mittel: Hash-Randomisierung |

## Praktische Interpretation

| Beobachtung | Praktische Aussage |
|---|---|
| `replay-current-exact` | Der aktuelle Firefox/NSS-Default kann exakt wiedererzwingt werden. |
| `exact-http1-compact`, `exact-tls12-http1` | Deutlich andere JA4-Fingerprints lassen sich gezielt und sauber erzeugen. |
| `exact-alt-signatures` | Einzelne Felder wie Signature Algorithms koennen gezielt den Hash-/Body-Teil verschieben, ohne die komplette Shape zu aendern. |
| `random-grease-only`, `random-both-run-*` | Randomisierung ist real sichtbar, wirkt hier aber meist nur auf den letzten JA4-Teil. |
| `reorder-prefix-http-fields`, `random-permute-only`, `exact-alt-groups` | Nicht jede interne NSS-Aenderung fuehrt zu einem sichtbar anderen JA4 am Endpoint. |
| `exact-h2-only` | Es gibt Konfigurationen, die intern akzeptiert werden, aber im Live-Abruf instabil bleiben. |

## Hinweis zu Brave-/Chromium-Profilen mit GREASE

Bei Profilen mit `enable_grease=true` kann ein Replay strukturell korrekt sein,
ohne dass der komplette JA4-Hash pro Lauf identisch bleibt.

Typisches Muster:

- TLS-Version, Cipher-Liste, Extension-IDs und ALPN stimmen
- der letzte JA4-Teil weicht trotzdem ab
- im `JA4_STRING` taucht ein zusaetzlicher GREASE-Wert wie `caca` auf

Das ist in der Regel keine kaputte Profiluebernahme, sondern erwartbare
GREASE-Varianz. Fuer eine faire Bewertung solcher Profile sollte man daher
unterscheiden zwischen:

- `strukturgetreu`: stabile Kernstruktur des `JA4_STRING` stimmt
- `hash-identisch`: kompletter JA4-Hash ist bitgenau gleich

Fuer streng reproduzierbare Experimente sollte GREASE deaktiviert werden.

## Bewertungslegende

- `Sehr hoch: exaktes Replay`: Der Baseline-Fingerprint wurde exakt reproduziert.
- `Hoch: gezieltes Spoofing`: Ein deutlich anderer JA4 wurde sauber und kontrolliert erreicht.
- `Mittel: partielles Spoofing`: Es aenderte sich ein relevanter Teil, aber nicht die ganze Shape.
- `Mittel: Hash-Randomisierung`: Die Randomisierung war am JA4 sichtbar, meist im letzten Segment.
- `Niedrig/kein sichtbarer Effekt`: Die NSS-Aenderung war am JA4-Endpoint nicht oder kaum sichtbar.
- `Fehlgeschlagen`: Der Live-Lauf hat keinen verwertbaren JA4-String geliefert.

Die autoritativen Rohdaten liegen direkt daneben als JSON und CSV.
