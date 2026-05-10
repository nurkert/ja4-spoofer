# Randomizer — How It Works

The randomizer generates a fresh TLS ClientHello fingerprint for each app on every roll. This document explains the concepts behind every setting so you can make informed choices.

---

## What is a TLS ClientHello and why does it matter?

When a browser opens an HTTPS connection it sends a **ClientHello** — the opening message of the TLS handshake. This message contains:

- A list of cipher suites the client is willing to use
- A list of TLS extensions (SNI, key_share, supported_groups, …)
- A list of signature algorithms

The **JA4 fingerprint** is a hash computed from these lists. Because different browsers send different lists in a different order, the fingerprint identifies the browser (or TLS stack) making the request — regardless of HTTP headers.

Crucially, the ClientHello is an **offer list, not a requirement**. The server reads it, picks whatever it supports best, and ignores everything else. This is the key property the randomizer exploits: you can add, remove, or reorder entries in the offer without changing which cipher or extension the server ultimately selects.

---

## JA4 sub-fields — what can change and what stays fixed

JA4 has three parts that are relevant here:

| Sub-field | Covers | Changes when… |
|-----------|--------|---------------|
| **JA4_a** | TLS version, SNI flag, **cipher count**, **extension count**, ALPN | D or J mutations alter the number of entries |
| **JA4_b** | Sorted hash of cipher suite IDs | S mutation swaps cipher IDs for different ones |
| **JA4_c** | Sorted hash of extension IDs | S mutation swaps extension IDs for different ones |

JA4_b and JA4_c are **sorted** hashes. Shuffling the wire order (mutation P) does not change them. To change JA4_b or JA4_c you must change which IDs are in the list, not just their order.

---

## Mutations — P, S, D, J

Each component (Cipher, Extension, SigAlg) can have any combination of four mutations applied:

**P — Permute**
Shuffles the wire order of IDs. Browsers send cipher suites in a characteristic order; permuting that order alone changes the observable ordering without touching the actual IDs. Because JA4_b/c are sorted before hashing, P alone does not change those sub-fields. Combine P with S for both order and ID variation.

**S — Swap**
Replaces some non-mandatory IDs with alternatives drawn from the Pool. The total count stays the same. This changes which IDs appear in the list → changes JA4_b and JA4_c. Has no effect on JA4_a (count unchanged).

**D — Drop**
Removes some non-mandatory IDs from the list. Count decreases → changes JA4_a (cipher count or extension count field). Mandatory IDs (see Safety Pins below) are never dropped.

**J — Junk (append)**
Appends extra IDs from the Pool at the end of the list. Count increases → changes JA4_a. Servers encounter extra entries they don't know and silently ignore them, so the connection itself is unaffected — as long as the IDs come from a reasonable pool (see below).

---

## Pool — where do S and J get their replacement/extra IDs from?

The Pool setting controls the source of IDs used by Swap and Append-junk.

**constrained**
Only the IDs this specific app already uses in its own ClientHello. Since the pool equals the current list, Swap has nothing new to swap in (no-op). J cannot append foreign IDs either. Fingerprint variation is limited to order (P) only.

**mixed** *(recommended)*
The app's own IDs plus a curated set of cipher suites and extensions observed in other real browsers (Chrome, Firefox, Safari). Servers encounter these routinely and handle them gracefully — they are part of the standard TLS offer of other mainstream clients. Swap picks from this wider set, giving real JA4_b/c variation. J can append entries that servers recognize and ignore. This pool produces meaningful fingerprint changes without breaking connectivity.

**chaos**
Completely random 16-bit IDs. The server has likely never seen most of them and may close the connection when it encounters an extension code it cannot parse or a cipher list it considers invalid. Use only for experiments where connection failures are acceptable.

---

## Safety Pins — why some IDs are never touched by default

TLS 1.3 requires certain cipher suites and extensions to be present for a valid handshake. Dropping or swapping them breaks the connection. By default the randomizer pins these IDs and never lets D or S touch them:

**Pinned ciphers** (TLS 1.3 mandatory per RFC 8446):
- `0x1301` TLS_AES_128_GCM_SHA256
- `0x1302` TLS_AES_256_GCM_SHA384
- `0x1303` TLS_CHACHA20_POLY1305_SHA256

**Pinned extensions** (required for a functioning TLS 1.3 handshake):
- `0x0000` server_name (SNI) — identifies the target hostname; dropping it breaks virtual-hosted HTTPS
- `0x000a` supported_groups — needed for key exchange
- `0x000d` signature_algorithms — needed for certificate validation
- `0x002b` supported_versions — signals TLS 1.3 support
- `0x002d` psk_key_exchange_modes — required when using session tickets
- `0x0033` key_share — carries the ephemeral key; without it TLS 1.3 cannot proceed

**Pinned signature algorithms**:
- `0x0403` ecdsa_secp256r1_sha256
- `0x0804` rsa_pss_rsae_sha256

**"Relax safety pins"** removes these protections, allowing D and S to modify the pinned IDs as well. This can produce more extreme fingerprint variation but will often cause handshake failures on real servers. Leave it off for normal use.

---

## Seed and determinism

Every roll is driven by a **master seed** (a 16-character hex string). From this seed the engine derives a per-app sub-seed using `SHA256(masterSeed + appId)`, so two apps always get different rolls even from the same master seed.

The same master seed + same settings always produces the same output. This means:
- You can reproduce a specific fingerprint by noting the seed.
- Changing a setting and then changing it back immediately restores the previous roll.
- Only clicking the refresh (🔄) icon or manually editing the seed field picks a new fingerprint.

---

## Recommended starting point

| Setting | Value | Reason |
|---------|-------|--------|
| Pool | mixed | Adds real-browser IDs; servers handle them without issues |
| Mutations | P + S | Shuffles order and swaps IDs → changes JA4_a order and JA4_b/c |
| Safety pins | off (default) | Keeps mandatory IDs; no connection failures |

Add **D** or **J** on Cipher and/or Extension when you also want JA4_a to vary (cipher count / extension count). Expect slightly less reliable connections if you enable J with a large junk amount on strict servers.
