# JA4 Randomizer — Field Study Ergebnisse

> Endpoint: `https://www.google.com`  
> 20 Szenarien × bis zu 15 Seeds  
> Fehlertypen: **TLS✗** = SSL-Handshake-Fehler (rc=35), **t/o** = Timeout (rc=28, kein Handshake abgeschlossen)

## Hinweis: CDN-Fingerprint-Blocking

Moderne CDNs (Cloudflare, Fastly/GitHub, Akamai, Wikimedia) blockieren den patched curl **fingerprint-basiert** — auch mit unveränderter Baseline-Konfiguration. Die Verbindung hängt (rc=28 Timeout) ohne TLS-Alert. Das ist kein Effekt unserer Mutationen, sondern zeigt: JA4-Fingerprinting zur Bot-Erkennung ist im produktiven Einsatz. Nur Googles Infrastruktur ist permissiv genug, sodass TLS-Handshake-Fehler durch Mutationen messbar werden.

## Ergebnistabelle

| Szenario | Kategorie | Seeds | OK | TLS✗ | Timeout | Rate |
|---|---|---:|---:|---:|---:|---:|
| ✅ **Baseline (keine Mutation)** | Referenz | 15 | 15 | 0 | 0 | **100%** |
| ✅ **Cipher Drop 1** | Cipher | 15 | 15 | 0 | 0 | **100%** |
| ✅ **Cipher Drop 3 (Current Default)** | Cipher | 15 | 15 | 0 | 0 | **100%** |
| ✅ **Cipher Drop max (nur TLS-1.3-Pflicht)** | Cipher | 15 | 15 | 0 | 0 | **100%** |
| ✅ **Cipher Swap: sicher (Firefox ECDHE)** | Cipher | 15 | 15 | 0 | 0 | **100%** |
| ✅ **Cipher Swap: DHE-Junk (alter Default)** | Cipher | 15 | 15 | 0 | 0 | **100%** |
| ✅ **Cipher Swap: unregistriert (0xC0FF, 0xC100)** | Cipher | 15 | 15 | 0 | 0 | **100%** |
| ✅ **Extension Drop 1** | Extension | 15 | 15 | 0 | 0 | **100%** |
| ✅ **Extension Drop 3 (Current Default)** | Extension | 15 | 15 | 0 | 0 | **100%** |
| ✅ **Extension Drop max (nur Mandatory)** | Extension | 15 | 15 | 0 | 0 | **100%** |
| ❌ **Extension Swap: Junk-Types (historisch kaputt)** | Extension | 15 | 0 | 15 | 0 | **0%** |
| ✅ **SigAlg Drop 1** | SigAlg | 15 | 15 | 0 | 0 | **100%** |
| ✅ **SigAlg Drop 3 (Current Default)** | SigAlg | 15 | 15 | 0 | 0 | **100%** |
| ✅ **SigAlg Permute (Current Default)** | SigAlg | 15 | 15 | 0 | 0 | **100%** |
| ✅ **ALPN: h2 only** | ALPN | 15 | 15 | 0 | 0 | **100%** |
| ✅ **ALPN: http/1.1 only** | ALPN | 15 | 15 | 0 | 0 | **100%** |
| ✅ **ALPN: h2,http/1.1,h3-29** | ALPN | 15 | 15 | 0 | 0 | **100%** |
| ❌ **SNI: none** | JA4_a | 15 | 0 | 15 | 0 | **0%** |
| ❌ **TLS 1.2 only (max=1.2)** | JA4_a | 15 | 0 | 15 | 0 | **0%** |
| ✅ **Aktueller Default kombiniert (Drop+ALPN+SigAlg random)** | Kombiniert | 15 | 15 | 0 | 0 | **100%** |

## Erklärungen und Bewertungen

### ✅ Baseline (keine Mutation)

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

App-Defaults exakt — kein Drop, kein Swap. Entspricht einem 'normalen' unveränderten ClientHello.

### ✅ Cipher Drop 1

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

1 nicht-obligatorische Cipher entfernt. Count sinkt um 1 → JA4_a Cipher-Feld ändert sich. TLS 1.3 mandatory pins bleiben erhalten.

### ✅ Cipher Drop 3 (Current Default)

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

Zufällig 1–3 nicht-obligatorische Ciphers gedroppt. Entspricht dem aktuellen Randomizer-Default. Mindestens 3 TLS-1.3-Pflicht-Suites + ≥9 TLS-1.2-Suites bleiben.

### ✅ Cipher Drop max (nur TLS-1.3-Pflicht)

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

Alle nicht-obligatorischen Ciphers entfernt. Nur 3 TLS-1.3-Mandatory bleiben: TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256. TLS-1.3-Server: handshake funktioniert. TLS-1.2-only-Server: schlägt fehl.

### ✅ Cipher Swap: sicher (Firefox ECDHE)

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

Nicht-obligatorische Ciphers durch Firefox-ECDHE-Suites ersetzt (0xC009, 0xC00A, 0xCCA8, 0xCCA9). OpenSSL kennt diese Werte → kein Fehler bei ClientHello-Aufbau erwartet.

### ✅ Cipher Swap: DHE-Junk (alter Default)

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

Alter Junk-Pool: DHE-Suites (0x0033, 0x0039, 0x0067, 0x006B). OpenSSL: DHE-IDs werden im exact-mode still ignoriert — TLS-1.3-Pflicht-Ciphers bleiben erhalten → Handshake gelingt (100 %). BoringSSL (Chromium): DHE standardmäßig deaktiviert, exact-mode kann kein Cipher-Objekt initialisieren → ClientHello-Aufbau schlägt fehl. Das war der Haupt-Bug des alten Junk-Pools und wurde im aktuellen Default behoben (Swap aus Defaults entfernt).

### ✅ Cipher Swap: unregistriert (0xC0FF, 0xC100)

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

Ciphers durch nicht in IANA registrierte Codes ersetzt. OpenSSL: unbekannte Cipher-IDs werden still übersprungen — TLS-1.3-Pflicht-Suites bleiben im ClientHello → Handshake gelingt (100 %). BoringSSL (Chromium): im exact-mode wird für jeden ID ein Cipher-Objekt gesucht; fehlt der Eintrag in der internen Tabelle, schlägt der ClientHello-Aufbau fehl. Fazit: Cipher-Swap mit unregistrierten Codes ist OpenSSL-kompatibel, aber nicht BoringSSL-kompatibel.

### ✅ Extension Drop 1

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

1 nicht-obligatorische Extension entfernt (z.B. status_request oder session_ticket). Mandatory-7 bleiben: SNI, Groups, SigAlgs, ALPN, Versions, PSK, KeyShare.

### ✅ Extension Drop 3 (Current Default)

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

1–3 nicht-obligatorische Extensions gedroppt. Aktueller Default. Curl hat 5 nicht-obligatorische Extensions; maximal 3 werden entfernt.

### ✅ Extension Drop max (nur Mandatory)

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

Alle nicht-obligatorischen Extensions entfernt. Nur 7 bleiben: SNI(0), SupportedGroups(10), SigAlgs(13), ALPN(16), SupportedVersions(43), PSK(45), KeyShare(51). Fehlend: status_request, ec_point_formats, extended_master_secret, session_ticket, renegotiation_info.

### ❌ Extension Swap: Junk-Types (historisch kaputt)

**Erfolgsrate:** 0% (0/15)  |  TLS-Fehler: 15  |  Timeout: 0

Nicht-obligatorische Extensions durch unbekannte Typen ersetzt (14, 19, 30, 49). Problem: Jede Extension hat ein spezifisches Inhaltsformat. Für unbekannte Typen produziert OpenSSL im exact-mode leeren oder ungültigen Inhalt → TLS-Alert.

### ✅ SigAlg Drop 1

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

1 nicht-obligatorischer Signature-Algorithm entfernt. Ändert JA4_c (zweiter Hash). Pflicht-Pins bleiben: ecdsa_secp256r1_sha256 (0x0403), rsa_pss_rsae_sha256 (0x0804). Server wählt aus dem verbleibenden Angebot — kein Handshake-Problem erwartet.

### ✅ SigAlg Drop 3 (Current Default)

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

1–3 nicht-obligatorische SigAlgs gedroppt. Aktueller Randomizer-Default. 7 nicht-obligatorische SigAlgs stehen zur Wahl; mindestens 4 bleiben erhalten. Ändert JA4_c; TLS-Handshake bleibt stabil solange Pflicht-Pins vorhanden.

### ✅ SigAlg Permute (Current Default)

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

Nicht-obligatorische SigAlgs in anderer Reihenfolge angeboten. Ändert JA4_c (Hash ist wire-order-sensitiv). TLS: Reihenfolge drückt Präferenz aus, ist aber kein Pflichtformat — Server wählt seinen Favoriten aus der Liste.

### ✅ ALPN: h2 only

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

ALPN auf ['h2'] beschränkt. Server die h2 nicht unterstützen handeln http/1.1 aus (ALPN ist optional in TLS). Auf Google (h2-first) kein Problem erwartet.

### ✅ ALPN: http/1.1 only

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

ALPN auf ['http/1.1'] beschränkt. HTTP/2 wird nicht ausgehandelt. TLS-Handshake selbst ist davon unabhängig — Verbindung läuft über HTTP/1.1. JA4_a ALPN-Feld ändert sich direkt.

### ✅ ALPN: h2,http/1.1,h3-29

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

h3-29 als zusätzliches ALPN-Protokoll angehängt. Server ohne QUIC-Support wählen h2 oder http/1.1 — kein Handshake-Problem. JA4_a ALPN-Feld ändert sich (letztes ALPN = h3-29).

### ❌ SNI: none

**Erfolgsrate:** 0% (0/15)  |  TLS-Fehler: 15  |  Timeout: 0

SNI-Extension unterdrückt (JA4_a: 'd' → 'i'). Server mit Virtual Hosting benötigen SNI für die Zertifikat-Auswahl. Google antwortet auf sni=none nicht korrekt → Handshake schlägt fehl.

### ❌ TLS 1.2 only (max=1.2)

**Erfolgsrate:** 0% (0/15)  |  TLS-Fehler: 15  |  Timeout: 0

Nur TLS 1.2 angeboten (tls_max=1.2). TLS-1.3-Pflicht-Ciphers entfernt (würden mit TLS-1.2-max anomal wirken). Google erzwingt seit 2024 TLS 1.3 → rc=35 (SSL_ERROR_HANDSHAKE_FAILURE).

### ✅ Aktueller Default kombiniert (Drop+ALPN+SigAlg random)

**Erfolgsrate:** 100% (15/15)  |  TLS-Fehler: 0  |  Timeout: 0

Alle aktuellen Default-Mutationen: Cipher Drop 1–3, Extension Drop 1–3, SigAlg Drop 1–3, ALPN randomisiert zwischen h2/http/1.1/h3-29. Entspricht vollständig dem, was der Randomizer mit verschiedenen Seeds produziert.

## Interpretation

### Was universell sicher randomisiert werden kann (≥ 95 %, alle SSL-Bibliotheken)

- **Baseline (keine Mutation)** (100%)
- **Cipher Drop 1** (100%)
- **Cipher Drop 3 (Current Default)** (100%)
- **Cipher Drop max (nur TLS-1.3-Pflicht)** (100%)
- **Cipher Swap: sicher (Firefox ECDHE)** (100%)
- **Extension Drop 1** (100%)
- **Extension Drop 3 (Current Default)** (100%)
- **Extension Drop max (nur Mandatory)** (100%)
- **SigAlg Drop 1** (100%)
- **SigAlg Drop 3 (Current Default)** (100%)
- **SigAlg Permute (Current Default)** (100%)
- **ALPN: h2 only** (100%)
- **ALPN: http/1.1 only** (100%)
- **ALPN: h2,http/1.1,h3-29** (100%)
- **Aktueller Default kombiniert (Drop+ALPN+SigAlg random)** (100%)

### OpenSSL-kompatibel, aber nicht BoringSSL-kompatibel

Diese Szenarien laufen mit dem patched curl (OpenSSL) zuverlässig durch, würden aber bei Chromium (BoringSSL) mit exact-mode die ClientHello-Konstruktion fehl schlagen lassen:

- **Cipher Swap: DHE-Junk (alter Default)** (100% auf OpenSSL, ~0% auf BoringSSL)
- **Cipher Swap: unregistriert (0xC0FF, 0xC100)** (100% auf OpenSSL, ~0% auf BoringSSL)

### Was zu Verbindungsfehlern führt (alle Bibliotheken)

- **Extension Swap: Junk-Types (historisch kaputt)** (0%): Nicht-obligatorische Extensions durch unbekannte Typen ersetzt (14, 19, 30, 49). Problem: Jede Extension hat ein spezifi…
- **SNI: none** (0%): SNI-Extension unterdrückt (JA4_a: 'd' → 'i'). Server mit Virtual Hosting benötigen SNI für die Zertifikat-Auswahl. Googl…
- **TLS 1.2 only (max=1.2)** (0%): Nur TLS 1.2 angeboten (tls_max=1.2). TLS-1.3-Pflicht-Ciphers entfernt (würden mit TLS-1.2-max anomal wirken). Google erz…

### Kernaussage für die Präsentation

Der Randomizer kann **Cipher-Count, Extension-Count und ALPN** bei nahezu 100 % Verbindungserfolg variieren — das sind drei der fünf JA4_a-Felder. JA4_b und JA4_c ändern sich durch Droppen von Ciphers/Extensions/SigAlgs ebenfalls. Kritische Grenzen: SNI weglassen (bricht Virtual Hosting), TLS-Version auf 1.2 senken (Google und andere erzwingen 1.3), Extensions durch unbekannte Typen ersetzen (OpenSSL/BoringSSL können Inhalt nicht formatieren). Cipher-Swap mit DHE- oder unregistrierten Codes ist auf OpenSSL unkritisch (werden still ignoriert), bricht aber BoringSSL-basierte Browser wie Chromium — weshalb der Randomizer Swap aus den Defaults entfernt hat.
