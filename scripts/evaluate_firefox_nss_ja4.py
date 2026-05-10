#!/usr/bin/env python3
"""Run a practical JA4 evaluation matrix against the patched Firefox/NSS build.

This script launches the locally built Firefox binary with different
NSS_JA4_CONFIG profiles, fetches a remote JA4 echo endpoint via Selenium,
captures the returned JA4 string, and stores a structured dataset as JSON,
CSV, and Markdown.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import tempfile
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from selenium import webdriver
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.service import Service


DEFAULT_BINARY = (
    Path.home()
    / "build/firefox-ja4-stable/gecko-dev/obj-ja4-stable/dist/Nightly.app/Contents/MacOS/firefox"
)
DEFAULT_URL = "https://ja4-observer.example/raw"


@dataclass(frozen=True)
class Case:
    name: str
    category: str
    description: str
    config_text: str | None = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Evaluate practical JA4 spoofing/randomization with patched Firefox/NSS."
    )
    parser.add_argument(
        "--binary",
        default=str(DEFAULT_BINARY),
        help=f"Firefox binary to use (default: {DEFAULT_BINARY})",
    )
    parser.add_argument(
        "--url",
        default=DEFAULT_URL,
        help=f"JA4 echo endpoint (default: {DEFAULT_URL})",
    )
    parser.add_argument(
        "--output-dir",
        default="docs/datasets",
        help="Directory for JSON/CSV/Markdown results (default: docs/datasets)",
    )
    return parser.parse_args()


def split_ja4(value: str) -> tuple[str, str, str]:
    parts = value.strip().split("_")
    if len(parts) != 3:
        return value.strip(), "", ""
    return parts[0], parts[1], parts[2]


def parse_part_a(part_a: str) -> dict[str, Any]:
    match = re.fullmatch(r"([a-z])(\d{2})([id])(\d{2})(\d{2})([a-z0-9]+)", part_a)
    if not match:
        return {"part_a_raw": part_a}
    transport, tls_version, sni_flag, cipher_count, ext_count, alpn = match.groups()
    return {
        "part_a_raw": part_a,
        "transport": transport,
        "tls_version_token": tls_version,
        "sni_flag": sni_flag,
        "cipher_count_token": int(cipher_count),
        "extension_count_token": int(ext_count),
        "alpn_token": alpn,
    }


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


def comma_len(value: str | None) -> int | None:
    if not value:
        return None
    return len([x for x in value.split(",") if x])


def run_case(case: Case, binary: Path, url: str) -> dict[str, Any]:
    profile_dir = Path(tempfile.mkdtemp(prefix="ff-ja4-prof-"))
    temp_dir = Path(tempfile.mkdtemp(prefix="ff-ja4-case-"))
    dump_path = temp_dir / "nss-dump.conf"
    cfg_path = temp_dir / "nss.conf"

    env = os.environ.copy()
    env.pop("NSS_JA4_CONFIG", None)
    env["NSS_JA4_DUMP"] = str(dump_path)

    if case.config_text is not None:
        cfg_path.write_text(textwrap.dedent(case.config_text).strip() + "\n")
        env["NSS_JA4_CONFIG"] = str(cfg_path)

    options = Options()
    options.binary_location = str(binary)
    options.accept_insecure_certs = True
    options.add_argument("-headless")
    options.add_argument("-no-remote")
    options.add_argument("-profile")
    options.add_argument(str(profile_dir))

    result: dict[str, Any] = {
        "name": case.name,
        "category": case.category,
        "description": case.description,
        "config_path": str(cfg_path) if case.config_text is not None else "",
    }

    driver = None
    try:
        service = Service(env=env)
        driver = webdriver.Firefox(options=options, service=service)
        driver.set_page_load_timeout(60)
        driver.get(url)
        body = driver.find_element("tag name", "body").text.strip()
        result["request_ok"] = True
        result["ja4"] = body
    except Exception as exc:  # pragma: no cover - for runtime capture only
        result["request_ok"] = False
        result["error"] = f"{type(exc).__name__}: {exc}"
        result["ja4"] = ""
    finally:
        if driver is not None:
            try:
                driver.quit()
            except Exception:
                pass
        shutil.rmtree(profile_dir, ignore_errors=True)

    dump = parse_dump(dump_path)
    for key in (
        "apply_ok",
        "mismatch_mask",
        "tls_min",
        "tls_max",
        "strict",
        "alpn",
        "sni_mode",
        "cipher_mode",
        "extension_mode",
        "cipher_suites",
        "cipher_count",
        "extension_order",
        "extension_count",
        "supported_versions",
        "supported_groups",
        "key_share_groups",
        "psk_key_exchange_modes",
        "signature_algorithms",
        "enable_grease",
        "enable_ch_xtn_permutation",
    ):
        if key in dump:
            result[key] = dump[key]

    if result["ja4"]:
        part_a, part_b, part_c = split_ja4(result["ja4"])
        result["part_a"] = part_a
        result["part_b"] = part_b
        result["part_c"] = part_c
        result.update(parse_part_a(part_a))

    result["dump_cipher_len"] = comma_len(result.get("cipher_suites"))
    result["dump_extension_len"] = comma_len(result.get("extension_order"))
    result["dump_group_len"] = comma_len(result.get("supported_groups"))
    result["dump_key_share_len"] = comma_len(result.get("key_share_groups"))

    shutil.rmtree(temp_dir, ignore_errors=True)
    return result


def add_comparisons(rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    baseline = rows[0]
    baseline_ja4 = baseline.get("ja4", "")
    baseline_a = baseline.get("part_a", "")
    baseline_b = baseline.get("part_b", "")
    baseline_c = baseline.get("part_c", "")

    for row in rows:
        row["matches_baseline_ja4"] = row.get("ja4", "") == baseline_ja4
        row["part_a_changed_vs_baseline"] = row.get("part_a", "") != baseline_a
        row["part_b_changed_vs_baseline"] = row.get("part_b", "") != baseline_b
        row["part_c_changed_vs_baseline"] = row.get("part_c", "") != baseline_c
        row["changed_segment_count_vs_baseline"] = sum(
            (
                row["part_a_changed_vs_baseline"],
                row["part_b_changed_vs_baseline"],
                row["part_c_changed_vs_baseline"],
            )
        )

        request_ok = bool(row.get("request_ok"))
        apply_ok = row.get("apply_ok") == "1"
        mismatch_ok = row.get("mismatch_mask") == "0"
        changed_count = row["changed_segment_count_vs_baseline"]
        category = row.get("category", "")

        if not request_ok:
            assessment = "failed"
        elif not apply_ok or not mismatch_ok:
            assessment = "partial"
        elif category == "baseline":
            assessment = "reference"
        elif category == "replay" and row["matches_baseline_ja4"]:
            assessment = "very_high_exact_replay"
        elif category == "targeted_exact" and changed_count >= 2:
            assessment = "high_targeted_spoof"
        elif category == "targeted_exact" and changed_count >= 1:
            assessment = "medium_targeted_spoof"
        elif category == "targeted_reorder" and changed_count >= 1:
            assessment = "medium_reorder_control"
        elif category == "randomized" and row["part_c_changed_vs_baseline"]:
            if row["part_a_changed_vs_baseline"] or row["part_b_changed_vs_baseline"]:
                assessment = "high_randomization"
            else:
                assessment = "medium_hash_randomization"
        else:
            assessment = "low_or_no_effect"

        row["assessment"] = assessment


def write_json(rows: list[dict[str, Any]], output_path: Path, meta: dict[str, Any]) -> None:
    payload = {"meta": meta, "rows": rows}
    output_path.write_text(json.dumps(payload, indent=2) + "\n")


def write_csv(rows: list[dict[str, Any]], output_path: Path) -> None:
    fieldnames: list[str] = []
    for row in rows:
        for key in row.keys():
            if key not in fieldnames:
                fieldnames.append(key)
    with output_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_markdown(rows: list[dict[str, Any]], output_path: Path, meta: dict[str, Any]) -> None:
    baseline = rows[0]
    assessment_labels = {
        "reference": "Referenz",
        "very_high_exact_replay": "Very high: exact replay",
        "high_targeted_spoof": "High: targeted spoof",
        "medium_targeted_spoof": "Medium: partial spoof",
        "medium_reorder_control": "Medium: reorder control",
        "medium_hash_randomization": "Medium: hash randomization",
        "high_randomization": "High: broad randomization",
        "low_or_no_effect": "Low/no visible effect",
        "partial": "Partial",
        "failed": "Failed",
    }
    category_labels = {
        "baseline": "Baseline",
        "replay": "Replay",
        "targeted_exact": "Targeted exact",
        "targeted_reorder": "Targeted reorder",
        "randomized": "Randomized",
    }

    successful_rows = [row for row in rows if row.get("request_ok")]
    exact_replay_count = sum(1 for row in rows if row.get("assessment") == "very_high_exact_replay")
    high_spoof_count = sum(1 for row in rows if row.get("assessment") == "high_targeted_spoof")
    randomization_count = sum(
        1 for row in rows if row.get("assessment") in {"medium_hash_randomization", "high_randomization"}
    )
    no_effect_count = sum(1 for row in rows if row.get("assessment") == "low_or_no_effect")

    lines = [
        "# Firefox NSS JA4 Practical Evaluation",
        "",
        f"- Binary: `{meta['binary']}`",
        f"- Endpoint: `{meta['url']}`",
        f"- Cases: `{len(rows)}`",
        f"- Baseline JA4: `{baseline.get('ja4', '')}`",
        "",
        "## Summary",
        "",
        f"- Successful live runs: `{len(successful_rows)}/{len(rows)}`",
        f"- Exact replay of the current default fingerprint: `{exact_replay_count}` case(s)",
        f"- Successful targeted changes to other JA4 values: `{high_spoof_count}` case(s)",
        f"- Visible randomization: `{randomization_count}` case(s)",
        f"- Low or no visible effect: `{no_effect_count}` case(s)",
        "",
        "The measurement shows that exact replay and targeted profile changes work well. "
        "In this setup, built-in randomization mostly changes the hash/body portion of JA4, "
        "not necessarily the full outer shape.",
        "",
        "## Results",
        "",
        "| Case | Type | Observed JA4 | Delta vs. baseline | Runtime status | Assessment |",
        "|---|---|---|---:|---|---|",
    ]
    for row in rows:
        request_state = "ok" if row.get("request_ok") else "request failed"
        if row.get("apply_ok") == "1" and row.get("mismatch_mask") == "0":
            request_state = f"{request_state}, apply_ok=1"
        elif row.get("apply_ok") is not None:
            request_state = (
                f"{request_state}, apply_ok={row.get('apply_ok','')}, mismatch={row.get('mismatch_mask','')}"
            )
        lines.append(
            "| {name} | {category} | `{ja4}` | {changed} | {state} | {assessment} |".format(
                name=row.get("name", ""),
                category=category_labels.get(row.get("category", ""), row.get("category", "")),
                ja4=row.get("ja4", ""),
                changed=row.get("changed_segment_count_vs_baseline", ""),
                state=request_state,
                assessment=assessment_labels.get(row.get("assessment", ""), row.get("assessment", "")),
            )
        )

    lines.extend(
        [
            "",
            "## Practical Interpretation",
            "",
            "| Observation | Practical meaning |",
            "|---|---|",
            "| `replay-current-exact` | The current Firefox/NSS default can be replayed exactly. |",
            "| `exact-http1-compact`, `exact-tls12-http1` | Clearly different JA4 fingerprints can be generated intentionally. |",
            "| `exact-alt-signatures` | Individual fields such as signature algorithms can shift the hash/body part without changing the full shape. |",
            "| `random-grease-only`, `random-both-run-*` | Randomization is visible, mostly in the final JA4 component for this setup. |",
            "| `reorder-prefix-http-fields`, `random-permute-only`, `exact-alt-groups` | Not every internal NSS change produces a visibly different JA4 value at the endpoint. |",
            "| `exact-h2-only` | Some configurations are accepted internally but remain unstable in live requests. |",
            "",
            "## Assessment Legend",
            "",
            "- `Very high: exact replay`: the baseline fingerprint was reproduced exactly.",
            "- `High: targeted spoof`: a clearly different JA4 value was reached intentionally.",
            "- `Medium: partial spoof`: one relevant part changed, but not the full shape.",
            "- `Medium: hash randomization`: randomization was visible in JA4, mostly in the last segment.",
            "- `Low/no visible effect`: the NSS change was not visible or barely visible at the endpoint.",
            "- `Failed`: the live run did not produce a usable JA4 string.",
            "",
            "The authoritative raw data is written next to this file as JSON and CSV.",
            "",
        ]
    )

    output_path.write_text("\n".join(lines))


def build_cases() -> list[Case]:
    return [
        Case(
            name="baseline-default",
            category="baseline",
            description="Current default patched Firefox fingerprint without explicit NSS_JA4_CONFIG.",
        ),
        Case(
            name="replay-current-exact",
            category="replay",
            description="Exact replay of the currently observed default fingerprint.",
            config_text="""
                strict=1
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                enable_ch_xtn_permutation=0
                cipher_mode=exact
                cipher_suites=4865,4867,4866,49195,49199,52393,52392,49196,49200,49171,49172,156,157,47,53
                alpn=h2,http/1.1
                supported_versions=772,771
                supported_groups=4588,29,23,24,25,256,257
                key_share_groups=4588,29,23
                psk_key_exchange_modes=1
                extension_mode=exact
                extension_order=0,23,65281,10,11,35,16,5,34,18,51,43,13,45,28,27,65037
                sni_mode=present
            """,
        ),
        Case(
            name="reorder-prefix-http-fields",
            category="targeted_reorder",
            description="Only reorder a chosen extension prefix while preserving the rest.",
            config_text="""
                strict=1
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                enable_ch_xtn_permutation=0
                extension_mode=reorder
                extension_order=16,43,13,45
                sni_mode=present
            """,
        ),
        Case(
            name="exact-http1-compact",
            category="targeted_exact",
            description="Exact TLS 1.3 profile with compact cipher list and HTTP/1.1 only.",
            config_text="""
                strict=1
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                enable_ch_xtn_permutation=0
                cipher_mode=exact
                cipher_suites=4865,4867,4866,49195,49199
                alpn=http/1.1
                signature_algorithms=1027,1283,1539,2052,2053
                supported_versions=772,771
                supported_groups=29,23,24
                key_share_groups=29
                psk_key_exchange_modes=1
                extension_mode=exact
                extension_order=0,23,65281,10,11,35,16,5,34,18,51,43,13,45,28,27
                sni_mode=present
            """,
        ),
        Case(
            name="exact-tls12-http1",
            category="targeted_exact",
            description="Force a TLS 1.2 / HTTP/1.1 style profile.",
            config_text="""
                strict=1
                tls_min=1.2
                tls_max=1.2
                enable_grease=0
                enable_ch_xtn_permutation=0
                alpn=http/1.1
                sni_mode=present
            """,
        ),
        Case(
            name="exact-h2-only",
            category="targeted_exact",
            description="Restrict ALPN to h2 only while keeping TLS 1.3 exact mode.",
            config_text="""
                strict=1
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                enable_ch_xtn_permutation=0
                cipher_mode=exact
                cipher_suites=4865,4867,4866,49195,49199,52393,52392
                alpn=h2
                supported_versions=772,771
                supported_groups=29,23,24
                key_share_groups=29
                psk_key_exchange_modes=1
                extension_mode=exact
                extension_order=0,23,65281,10,11,35,16,5,34,18,51,43,13,45,28,27
                sni_mode=present
            """,
        ),
        Case(
            name="exact-alt-groups",
            category="targeted_exact",
            description="Use a narrower group and key_share set.",
            config_text="""
                strict=1
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                enable_ch_xtn_permutation=0
                alpn=h2,http/1.1
                supported_versions=772,771
                supported_groups=29,23
                key_share_groups=29
                psk_key_exchange_modes=1
                extension_mode=exact
                extension_order=0,23,65281,10,11,35,16,5,34,18,51,43,13,45,28,27
                sni_mode=present
            """,
        ),
        Case(
            name="exact-alt-signatures",
            category="targeted_exact",
            description="Alter the signature algorithm ordering in exact mode.",
            config_text="""
                strict=1
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                enable_ch_xtn_permutation=0
                alpn=h2,http/1.1
                signature_algorithms=2052,2053,1027,1283
                supported_versions=772,771
                supported_groups=29,23,24
                key_share_groups=29
                psk_key_exchange_modes=1
                extension_mode=exact
                extension_order=0,23,65281,10,11,35,16,5,34,18,51,43,13,45,28,27
                sni_mode=present
            """,
        ),
        Case(
            name="random-grease-only",
            category="randomized",
            description="Enable GREASE while keeping extension permutation disabled.",
            config_text="""
                tls_min=1.2
                tls_max=1.3
                enable_grease=1
                enable_ch_xtn_permutation=0
                sni_mode=present
            """,
        ),
        Case(
            name="random-permute-only",
            category="randomized",
            description="Enable extension permutation while GREASE remains disabled.",
            config_text="""
                tls_min=1.2
                tls_max=1.3
                enable_grease=0
                enable_ch_xtn_permutation=1
                sni_mode=present
            """,
        ),
        Case(
            name="random-both-run-1",
            category="randomized",
            description="Combined GREASE and extension permutation, run 1.",
            config_text="""
                tls_min=1.2
                tls_max=1.3
                enable_grease=1
                enable_ch_xtn_permutation=1
                sni_mode=present
            """,
        ),
        Case(
            name="random-both-run-2",
            category="randomized",
            description="Combined GREASE and extension permutation, run 2.",
            config_text="""
                tls_min=1.2
                tls_max=1.3
                enable_grease=1
                enable_ch_xtn_permutation=1
                sni_mode=present
            """,
        ),
        Case(
            name="random-both-run-3",
            category="randomized",
            description="Combined GREASE and extension permutation, run 3.",
            config_text="""
                tls_min=1.2
                tls_max=1.3
                enable_grease=1
                enable_ch_xtn_permutation=1
                sni_mode=present
            """,
        ),
    ]


def main() -> int:
    args = parse_args()
    binary = Path(args.binary).expanduser().resolve()
    if not binary.exists():
        raise SystemExit(f"Firefox binary not found: {binary}")

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    cases = build_cases()
    rows = [run_case(case, binary=binary, url=args.url) for case in cases]
    add_comparisons(rows)

    meta = {
        "binary": str(binary),
        "url": args.url,
        "case_count": len(rows),
    }

    stem = output_dir / "firefox_nss_ja4_evaluation"
    write_json(rows, stem.with_suffix(".json"), meta)
    write_csv(rows, stem.with_suffix(".csv"))
    write_markdown(rows, stem.with_suffix(".md"), meta)

    print(json.dumps({"meta": meta, "output_prefix": str(stem)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
