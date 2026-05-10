#!/usr/bin/env python3
"""Run a practical JA4 evaluation matrix against the patched BoringSSL bssl tool.

This script launches ``bssl client`` with different BORINGSSL_JA4_CONFIG
profiles and:

  1. Queries a JA4 observation endpoint to get the server-observed JA4 string.
  2. Captures BORINGSSL_JA4_DUMP to additionally compute a local JA4 from
     wire-level fields for cross-verification.
  3. Stores a structured dataset as JSON, CSV, and Markdown.

The live JA4 from the endpoint is the authoritative result because the server
sees the actual ClientHello on the wire. The local computation is used to
verify the dump parsing pipeline.

Key insight: ``bssl client`` reads stdin → SSL and writes SSL → stdout.
The HTTP request must be followed by a short ``sleep`` so the socket stays
open long enough for the server response to arrive before the process exits.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import textwrap
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_BINARY = Path.home() / "build/boringssl-ja4-standalone/bssl"
DEFAULT_CONNECT = "ja4-observer.example:443"

# All valid GREASE values per RFC 8701.
_GREASE_VALUES: frozenset[int] = frozenset(
    v | (v << 8) for v in (0x0A, 0x1A, 0x2A, 0x3A, 0x4A, 0x5A, 0x6A, 0x7A,
                            0x8A, 0x9A, 0xAA, 0xBA, 0xCA, 0xDA, 0xEA, 0xFA)
)

_TLS_VERSION_MAP: dict[int, str] = {
    772: "13",
    771: "12",
    770: "11",
    769: "10",
}


# ---------------------------------------------------------------------------
# JA4 local computation from dump fields
# ---------------------------------------------------------------------------

def _is_grease(value: int) -> bool:
    return value in _GREASE_VALUES


def _csv_ints(value: str | None) -> list[int]:
    if not value:
        return []
    result = []
    for token in value.split(","):
        token = token.strip()
        if token:
            try:
                result.append(int(token))
            except ValueError:
                pass
    return result


def _tls_version_token(versions: list[int]) -> str:
    """Return JA4 version token from the highest non-GREASE supported version."""
    for v in versions:
        if not _is_grease(v) and v in _TLS_VERSION_MAP:
            return _TLS_VERSION_MAP[v]
    return "00"


def _alpn_token(alpn_raw: str | None) -> str:
    """Return 2-char ALPN token per JA4 spec: first char + last char of first protocol.
    E.g. 'h2' → 'h2', 'http/1.1' → 'h1', 'spdy/3.1' → 's1'. Returns '00' if absent."""
    if not alpn_raw:
        return "00"
    first = alpn_raw.split(",")[0].strip()
    if not first:
        return "00"
    if len(first) == 1:
        return first + first
    return first[0] + first[-1]


def compute_ja4_from_dump(dump: dict[str, str]) -> str:
    """Compute the raw JA4 fingerprint from BORINGSSL_JA4_DUMP fields.

    Returns the JA4 string in the form ``t13d{CC}{EE}{alpn}_{B}_{C}`` where
    B and C are the first 12 hex chars of their respective SHA-256 digests.
    Returns an empty string if essential fields are missing.
    """
    ciphers_raw = _csv_ints(dump.get("final_cipher_suites"))
    extensions_raw = _csv_ints(dump.get("final_extension_order"))
    sigalgs_raw = _csv_ints(dump.get("final_signature_algorithms"))
    versions_raw = _csv_ints(dump.get("final_supported_versions"))

    if not ciphers_raw and not extensions_raw:
        return ""

    # Filter GREASE from ciphers and count.
    ciphers = [c for c in ciphers_raw if not _is_grease(c)]
    cipher_count = len(ciphers)

    # Filter GREASE from extensions; SNI (0) counts for Part A but not Part C.
    extensions_no_grease = [e for e in extensions_raw if not _is_grease(e)]
    ext_count = len(extensions_no_grease)
    # Part C excludes SNI (0) AND ALPN (16) per JA4 spec.
    extensions_for_c = [e for e in extensions_no_grease if e != 0 and e != 16]

    # TLS version: prefer supported_versions extension, fall back to effective_tls_max dump field.
    if versions_raw:
        tls_ver = _tls_version_token(versions_raw)
    else:
        tls_max_raw = dump.get("effective_tls_max", "")
        tls_ver = _TLS_VERSION_MAP.get(int(tls_max_raw), "00") if tls_max_raw.isdigit() else "00"

    # SNI flag: 'd' if SNI extension (type 0) is present, 'i' otherwise.
    sni_flag = "d" if 0 in extensions_no_grease else "i"

    alpn_tok = _alpn_token(dump.get("requested_alpn"))

    # Part A
    part_a = (
        f"t{tls_ver}{sni_flag}"
        f"{cipher_count:02d}{ext_count:02d}"
        f"{alpn_tok}"
    )

    # Part B: SHA256 of sorted ciphers (4-char lowercase hex, comma-separated).
    sorted_cipher_str = ",".join(f"{c:04x}" for c in sorted(ciphers))
    part_b = hashlib.sha256(sorted_cipher_str.encode()).hexdigest()[:12]

    # Part C: SHA256 of sorted extensions (excl. SNI) + "_" + sigalgs in WIRE order.
    # Note: JA4 spec sorts extensions but keeps sigalgs in their original wire order.
    sorted_ext_str = ",".join(f"{e:04x}" for e in sorted(extensions_for_c))
    sig_str = ",".join(f"{s:04x}" for s in sigalgs_raw)
    part_c_input = f"{sorted_ext_str}_{sig_str}"
    part_c = hashlib.sha256(part_c_input.encode()).hexdigest()[:12]

    return f"{part_a}_{part_b}_{part_c}"


# ---------------------------------------------------------------------------
# Case definition
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Case:
    name: str
    category: str
    description: str
    config_text: str | None = None


def build_cases() -> list[Case]:
    # Baseline bssl fingerprint:
    #   ciphers: 4865,4866,4867,49195,49199,49196,49200,52393,52392,49161,
    #            49171,49162,49172,156,157,47,53
    #   extensions: 0,23,65281,10,11,35,13,51,45,43
    #   sigalgs: 1027,2052,1025,1283,2053,1281,2054,1537,513
    return [
        Case(
            name="baseline-default",
            category="baseline",
            description="Default bssl fingerprint — no JA4 config, pure upstream BoringSSL output.",
        ),
        Case(
            name="replay-baseline-exact",
            category="replay",
            description="Exact replay of the observed default bssl fingerprint.",
            config_text="""
                strict=1
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                enable_ch_xtn_permutation=0
                cipher_mode=exact
                cipher_suites=4865,4866,4867,49195,49199,49196,49200,52393,52392,49161,49171,49162,49172,156,157,47,53
                alpn=h2,http/1.1
                supported_versions=772,771
                supported_groups=29,23,24
                key_share_groups=29
                psk_key_exchange_modes=1
                signature_algorithms=1027,2052,1025,1283,2053,1281,2054,1537,513
                extension_mode=exact
                extension_order=0,23,65281,10,11,35,13,51,45,43
                sni_mode=present
            """,
        ),
        Case(
            name="exact-compact-tls13",
            category="targeted_exact",
            description="Exact TLS 1.3-only profile: only three TLS 1.3 ciphers, minimal extensions.",
            config_text="""
                strict=1
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                enable_ch_xtn_permutation=0
                cipher_mode=exact
                cipher_suites=4865,4866,4867
                alpn=h2,http/1.1
                supported_versions=772,771
                supported_groups=29,23,24
                key_share_groups=29
                psk_key_exchange_modes=1
                signature_algorithms=1027,2052,1283,2053
                extension_mode=exact
                extension_order=0,10,13,16,51,45,43,23,65281
                sni_mode=present
            """,
        ),
        Case(
            name="exact-http1-tls12only",
            category="targeted_exact",
            description="TLS 1.2 max, HTTP/1.1 only ALPN, reduced cipher list.",
            config_text="""
                strict=1
                tls_min=1.2
                tls_max=1.2
                enable_grease=0
                enable_ch_xtn_permutation=0
                cipher_mode=exact
                cipher_suites=49195,49199,49196,49200,49171,49172,156,157,47,53
                alpn=http/1.1
                supported_versions=771
                supported_groups=29,23,24
                key_share_groups=29
                signature_algorithms=1027,2052,1283,2053,1281,2054
                extension_mode=exact
                extension_order=0,10,11,35,13,23,65281
                sni_mode=present
            """,
        ),
        Case(
            name="reorder-cipher-prefix",
            category="targeted_reorder",
            description="Reorder: put ChaCha20 and AES-256 first before default ordering.",
            config_text="""
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                cipher_mode=reorder
                cipher_suites=4867,4866,49196,49200
                sni_mode=present
            """,
        ),
        Case(
            name="reorder-ext-prefix",
            category="targeted_reorder",
            description="Reorder: put sigalgs and supported_versions first in extension list.",
            config_text="""
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                extension_mode=reorder
                extension_order=13,43,51,45,10
                sni_mode=present
            """,
        ),
        Case(
            name="grease-on-fixed-3a3a",
            category="targeted_exact",
            description="GREASE enabled with fixed deterministic value 0x3a3a for reproducibility.",
            config_text="""
                tls_min=1.2
                tls_max=1.3
                enable_grease=1
                grease_value=0x3a3a
                sni_mode=present
            """,
        ),
        Case(
            name="grease-off-no-permute",
            category="targeted_exact",
            description="GREASE disabled, extension permutation disabled — fully deterministic output.",
            config_text="""
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                enable_ch_xtn_permutation=0
                sni_mode=present
            """,
        ),
        Case(
            name="exact-chromium-like",
            category="targeted_exact",
            description=(
                "Chromium/BoringSSL default profile from chromium-boringssl-ja4.yaml: "
                "TLS 1.3 preferred, h2+http/1.1, standard Chromium extension set."
            ),
            config_text="""
                strict=1
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                enable_ch_xtn_permutation=0
                cipher_mode=exact
                cipher_suites=4865,4866,4867,49195,49199,49196,49200,52393,52392,49161,49171,49162,49172,156,157,47,53
                alpn=h2,http/1.1
                supported_versions=772,771
                supported_groups=29,23,24
                key_share_groups=29
                psk_key_exchange_modes=1
                signature_algorithms=1027,2052,1025,1283,2053,1281,2054,1537,513
                extension_mode=exact
                extension_order=0,23,65281,10,11,35,16,5,18,51,43,13,45,27
                sni_mode=present
            """,
        ),
        Case(
            name="sni-suppressed",
            category="targeted_exact",
            description="SNI suppressed (sni_mode=none) — JA4 sni_flag becomes 'i'.",
            config_text="""
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                sni_mode=none
            """,
        ),
        Case(
            name="alt-sigalgs-sha384-only",
            category="targeted_exact",
            description="Only SHA-384 signature algorithms — changes JA4 Part C hash.",
            config_text="""
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                signature_algorithms=1283,2053,1281
                sni_mode=present
            """,
        ),
        Case(
            name="psk-modes-both",
            category="targeted_exact",
            description="Both PSK key-exchange modes (psk_ke=0 + psk_dhe_ke=1).",
            config_text="""
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                psk_key_exchange_modes=0,1
                sni_mode=present
            """,
        ),
    ]


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

def parse_dump(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


def _parse_live_ja4(stdout: bytes) -> str:
    """Extract the JA4 fingerprint from the bssl client stdout (HTTP response body)."""
    text = stdout.decode(errors="replace")
    # Strip HTTP headers: body is after the first blank line.
    if "\r\n\r\n" in text:
        body = text.split("\r\n\r\n", 1)[1]
    elif "\n\n" in text:
        body = text.split("\n\n", 1)[1]
    else:
        body = text
    # The body should be the raw JA4 string (e.g. "t13d171000_abc...").
    for line in body.splitlines():
        line = line.strip()
        if line.startswith("t") and "_" in line:
            return line
    return ""


def run_case(
    case: Case,
    binary: Path,
    connect: str,
    timeout: int,
) -> dict[str, Any]:
    temp_dir = Path(tempfile.mkdtemp(prefix="bssl-ja4-"))
    dump_path = temp_dir / "boringssl-dump.conf"
    cfg_path = temp_dir / "boringssl.conf"

    env = os.environ.copy()
    env.pop("BORINGSSL_JA4_CONFIG", None)
    env["BORINGSSL_JA4_DUMP"] = str(dump_path)

    if case.config_text is not None:
        cfg_path.write_text(textwrap.dedent(case.config_text).strip() + "\n")
        env["BORINGSSL_JA4_CONFIG"] = str(cfg_path)

    host = connect.split(":")[0]
    cmd = [str(binary), "client", "-connect", connect, "-server-name", host]

    # Send a valid HTTP/1.0 GET request followed by a short sleep so the
    # socket stays open long enough for the server response to arrive before
    # the process exits (bssl exits as soon as stdin closes).
    http_request = (
        f"GET /raw HTTP/1.0\r\n"
        f"Host: {host}\r\n"
        f"Connection: close\r\n"
        f"\r\n"
    ).encode()

    result: dict[str, Any] = {
        "name": case.name,
        "category": case.category,
        "description": case.description,
        "config": cfg_path.read_text() if case.config_text is not None else "",
    }

    try:
        # bssl exits when stdin is closed (EOF). We must keep stdin open long
        # enough for the server to receive the request and respond.
        # Strategy: use Popen, write the HTTP request, sleep to give the server
        # time to respond, then call communicate() to close stdin and collect
        # remaining output.
        _RESPONSE_WAIT = 3  # seconds — sufficient for a low-latency server
        proc = subprocess.Popen(
            cmd,
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        proc.stdin.write(http_request)  # type: ignore[union-attr]
        proc.stdin.flush()  # type: ignore[union-attr]
        time.sleep(_RESPONSE_WAIT)
        stdout, stderr = proc.communicate(timeout=timeout)
        result["connect_ok"] = proc.returncode == 0
        result["stderr_snippet"] = stderr.decode(errors="replace")[:400]
        live_ja4 = _parse_live_ja4(stdout)
        result["ja4"] = live_ja4
        result["request_ok"] = bool(live_ja4)
    except subprocess.TimeoutExpired:
        proc.kill()  # type: ignore[possibly-undefined]
        result["connect_ok"] = False
        result["request_ok"] = False
        result["error"] = "timeout"
        result["stderr_snippet"] = ""
        result["ja4"] = ""
    except Exception as exc:
        result["connect_ok"] = False
        result["request_ok"] = False
        result["error"] = str(exc)
        result["stderr_snippet"] = ""
        result["ja4"] = ""

    dump = parse_dump(dump_path)
    result["dump"] = dump

    # Copy key dump fields to top level for easy CSV access.
    for key in (
        "active",
        "apply_ok",
        "mismatch_mask",
        "effective_tls_min",
        "effective_tls_max",
        "strict",
        "sni_mode",
        "enable_grease",
        "enable_ch_xtn_permutation",
        "effective_grease_cipher",
        "final_cipher_suites",
        "final_extension_order",
        "final_signature_algorithms",
        "final_supported_versions",
        "final_supported_groups",
        "final_key_share_groups",
        "final_psk_key_exchange_modes",
        "requested_alpn",
    ):
        if key in dump:
            result[key] = dump[key]

    # Local JA4 computed from wire dump fields (cross-verification).
    ja4_local = compute_ja4_from_dump(dump)
    result["ja4_local"] = ja4_local

    # Use live JA4 as primary; fallback to local computation.
    primary_ja4 = result.get("ja4") or ja4_local
    if primary_ja4:
        parts = primary_ja4.split("_")
        result["ja4_part_a"] = parts[0] if len(parts) > 0 else ""
        result["ja4_part_b"] = parts[1] if len(parts) > 1 else ""
        result["ja4_part_c"] = parts[2] if len(parts) > 2 else ""

    # Flag if local and live JA4 match (sanity check).
    if result.get("ja4") and ja4_local:
        result["local_live_match"] = result["ja4"] == ja4_local

    shutil.rmtree(temp_dir, ignore_errors=True)
    return result


# ---------------------------------------------------------------------------
# Assessment + comparisons
# ---------------------------------------------------------------------------

def _primary_ja4(row: dict[str, Any]) -> str:
    """Return the authoritative JA4 for a row: live endpoint first, then local."""
    return row.get("ja4") or row.get("ja4_local", "")


def add_comparisons(rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    baseline = rows[0]
    baseline_ja4 = _primary_ja4(baseline)
    baseline_a = baseline.get("ja4_part_a", "")
    baseline_b = baseline.get("ja4_part_b", "")
    baseline_c = baseline.get("ja4_part_c", "")

    for row in rows:
        row["matches_baseline_ja4"] = _primary_ja4(row) == baseline_ja4
        row["part_a_changed"] = row.get("ja4_part_a", "") != baseline_a
        row["part_b_changed"] = row.get("ja4_part_b", "") != baseline_b
        row["part_c_changed"] = row.get("ja4_part_c", "") != baseline_c
        row["changed_segment_count"] = sum([
            row["part_a_changed"],
            row["part_b_changed"],
            row["part_c_changed"],
        ])

        connect_ok = bool(row.get("connect_ok"))
        apply_ok = row.get("apply_ok") == "1"
        mismatch_ok = row.get("mismatch_mask") == "0"
        has_ja4 = bool(_primary_ja4(row))
        changed = row["changed_segment_count"]
        category = row.get("category", "")

        if not connect_ok or not has_ja4:
            assessment = "failed"
        elif not apply_ok or not mismatch_ok:
            assessment = "partial"
        elif category == "baseline":
            assessment = "reference"
        elif category == "replay" and row.get("matches_baseline_ja4"):
            assessment = "very_high_exact_replay"
        elif category == "targeted_exact" and changed >= 2:
            assessment = "high_targeted_spoof"
        elif category == "targeted_exact" and changed >= 1:
            assessment = "medium_targeted_spoof"
        elif category == "targeted_exact" and not changed:
            assessment = "low_or_no_effect"
        elif category == "targeted_reorder" and changed >= 1:
            assessment = "medium_reorder_control"
        else:
            assessment = "low_or_no_effect"

        row["assessment"] = assessment


# ---------------------------------------------------------------------------
# Output writers
# ---------------------------------------------------------------------------

_ASSESSMENT_LABELS: dict[str, str] = {
    "reference": "Reference",
    "very_high_exact_replay": "Very high: exact replay",
    "high_targeted_spoof": "High: targeted spoof",
    "medium_targeted_spoof": "Medium: partial spoof",
    "medium_reorder_control": "Medium: reorder control",
    "low_or_no_effect": "Low/no visible effect",
    "partial": "Partial (apply_ok=0 or mismatch)",
    "failed": "Failed",
}

_CATEGORY_LABELS: dict[str, str] = {
    "baseline": "Baseline",
    "replay": "Replay",
    "targeted_exact": "Targeted exact",
    "targeted_reorder": "Targeted reorder",
}


def write_json(
    rows: list[dict[str, Any]], output_path: Path, meta: dict[str, Any]
) -> None:
    # Exclude raw dump dict from JSON rows to keep it clean; dump is already
    # flattened into top-level fields.
    clean_rows = [{k: v for k, v in r.items() if k != "dump"} for r in rows]
    output_path.write_text(
        json.dumps({"meta": meta, "rows": clean_rows}, indent=2) + "\n"
    )


def write_csv(rows: list[dict[str, Any]], output_path: Path) -> None:
    exclude = {"dump", "stderr_snippet", "config"}
    fieldnames: list[str] = []
    for row in rows:
        for key in row:
            if key not in exclude and key not in fieldnames:
                fieldnames.append(key)
    with output_path.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_markdown(
    rows: list[dict[str, Any]], output_path: Path, meta: dict[str, Any]
) -> None:
    baseline = rows[0]

    successful = [r for r in rows if r.get("connect_ok")]
    exact_replays = sum(1 for r in rows if r.get("assessment") == "very_high_exact_replay")
    high_spoof = sum(1 for r in rows if r.get("assessment") == "high_targeted_spoof")
    no_effect = sum(1 for r in rows if r.get("assessment") == "low_or_no_effect")

    lines = [
        "# BoringSSL bssl JA4 Practical Evaluation",
        "",
        f"- Binary: `{meta['binary']}`",
        f"- Endpoint: `{meta['connect']}`",
        f"- Cases: `{len(rows)}`",
        f"- Baseline JA4 (live): `{_primary_ja4(baseline)}`",
        f"- Baseline JA4 (local): `{baseline.get('ja4_local', '')}`",
        "",
        "## Summary",
        "",
        f"- Successful connections: `{len(successful)}/{len(rows)}`",
        f"- Exact replay of the default fingerprint: `{exact_replays}` case(s)",
        f"- Successful targeted changes to other JA4 values: `{high_spoof}` case(s)",
        f"- No visible effect: `{no_effect}` case(s)",
        "",
        (
            "JA4 is computed locally from wire-level fields in BORINGSSL_JA4_DUMP. "
            "Cipher suites, extension order and signature algorithms come directly from "
            "the serialized ClientHello, which makes the result equivalent to a server-side JA4 echo."
        ),
        "",
        "## Results",
        "",
        "| Case | Type | JA4 (live) | JA4 (local) | Delta vs. baseline | apply_ok | Assessment |",
        "|---|---|---|---|---:|---|---|",
    ]

    for row in rows:
        apply_state = (
            f"ok (mask={row.get('mismatch_mask', '?')})"
            if row.get("apply_ok") == "1"
                else f"NO (mask={row.get('mismatch_mask', '?')})"
        )
        lines.append(
            "| {name} | {cat} | `{ja4_live}` | `{ja4_local}` | {delta} | {apply} | {assess} |".format(
                name=row.get("name", ""),
                cat=_CATEGORY_LABELS.get(row.get("category", ""), row.get("category", "")),
                ja4_live=row.get("ja4", ""),
                ja4_local=row.get("ja4_local", ""),
                delta=row.get("changed_segment_count", ""),
                apply=apply_state if row.get("connect_ok") else "—",
                assess=_ASSESSMENT_LABELS.get(
                    row.get("assessment", ""), row.get("assessment", "")
                ),
            )
        )

    lines += [
        "",
        "## Assessment Legend",
        "",
        "- **Very high: exact replay** — baseline fingerprint reproduced exactly.",
        "- **High: targeted spoof** — clearly different JA4 produced intentionally (>=2 segments).",
        "- **Medium: partial spoof** — one segment changed.",
        "- **Medium: reorder control** — order visibly changed.",
        "- **Low/no visible effect** — JA4 identical to baseline.",
        "- **Partial** — apply_ok=0 or mismatch_mask!=0.",
        "- **Failed** — connection or dump failed.",
        "",
        "## Method Notes",
        "",
        "- JA4 is computed locally from `BORINGSSL_JA4_DUMP` (`final_cipher_suites`,",
        "  `final_extension_order`, `final_signature_algorithms`, `final_supported_versions`).",
        "- GREASE values (0x0a0a-0xfafa) are filtered before JA4 computation.",
        "- `final_*` fields reflect the wire bytes actually sent in the ClientHello.",
        "- No browser, Selenium or external JA4 echo endpoint is required.",
        "",
        "The authoritative raw data is written next to this file as JSON and CSV.",
        "",
    ]

    output_path.write_text("\n".join(lines))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Evaluate JA4 fingerprint spoofing with the patched BoringSSL bssl tool."
        )
    )
    parser.add_argument(
        "--binary",
        default=str(DEFAULT_BINARY),
        help=f"Path to bssl binary (default: {DEFAULT_BINARY})",
    )
    parser.add_argument(
        "--connect",
        default=DEFAULT_CONNECT,
        help=f"host:port to connect to (default: {DEFAULT_CONNECT})",
    )
    parser.add_argument(
        "--output-dir",
        default="docs/datasets",
        help="Directory for JSON/CSV/Markdown results (default: docs/datasets)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=15,
        help="Per-case timeout in seconds (default: 15)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    binary = Path(args.binary)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if not binary.exists():
        raise SystemExit(
            f"[error] bssl binary not found: {binary}\n"
            "Build with: scripts/build_boringssl.sh"
        )

    cases = build_cases()
    rows: list[dict[str, Any]] = []

    print(f"[info] Binary:  {binary}")
    print(f"[info] Connect: {args.connect}")
    print(f"[info] Cases:   {len(cases)}")
    print()

    for case in cases:
        print(f"  running: {case.name} ...", end=" ", flush=True)
        row = run_case(case, binary, args.connect, args.timeout)
        rows.append(row)
        status = row.get("assessment", "?")
        ja4 = _primary_ja4(row)
        local_match = "✓" if row.get("local_live_match") else ("≈" if row.get("ja4_local") else "")
        print(f"{status}  →  {ja4}  {local_match}")

    add_comparisons(rows)

    meta: dict[str, Any] = {
        "binary": str(binary),
        "connect": args.connect,
        "case_count": len(rows),
        "baseline_ja4_live": _primary_ja4(rows[0]) if rows else "",
        "baseline_ja4_local": rows[0].get("ja4_local", "") if rows else "",
    }

    json_path = output_dir / "boringssl_ja4_evaluation.json"
    csv_path = output_dir / "boringssl_ja4_evaluation.csv"
    md_path = output_dir / "boringssl_ja4_evaluation.md"

    write_json(rows, json_path, meta)
    write_csv(rows, csv_path)
    write_markdown(rows, md_path, meta)

    print()
    print(f"[info] Results written to {output_dir}/")
    print(f"         {json_path.name}")
    print(f"         {csv_path.name}")
    print(f"         {md_path.name}")


if __name__ == "__main__":
    main()
