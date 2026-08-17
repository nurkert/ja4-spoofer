#!/usr/bin/env python3
"""Offline consistency check for tests/ja4-fixtures/.

Every positive fixture claims an `expected_ja4`. That claim is only meaningful
if it is reproducible from the fixture's own `.conf` — otherwise the fixture
asserts a value no run can ever produce, and the acceptance harness can only
ever pass by *not* comparing the hash.

This script recomputes the JA4 from each `.conf` per the FoxIO spec and
compares it against the recorded `expected_ja4`. It also enforces the two
config invariants the patched stacks would otherwise resolve behind the
user's back:

  * extension-id closure — a configured body override (signature_algorithms,
    supported_groups, key_share_groups, supported_versions,
    psk_key_exchange_modes, alpn, sni) requires its extension id in
    `extension_order`. The patches append a missing id silently, which changes
    the extension count and therefore the JA4.
  * key_share_groups must be a subset of supported_groups (RFC 8446).

Run without arguments to check; pass --fix to rewrite the fixtures in place.
Needs no build, no network and no patched library, so CI can run it.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURE_DIR = REPO_ROOT / "tests" / "ja4-fixtures"

# RFC 8701 GREASE values; excluded from JA4 everywhere.
GREASE = {
    0x0A0A, 0x1A1A, 0x2A2A, 0x3A3A, 0x4A4A, 0x5A5A, 0x6A6A, 0x7A7A,
    0x8A8A, 0x9A9A, 0xAAAA, 0xBABA, 0xCACA, 0xDADA, 0xEAEA, 0xFAFA,
}

EXT_SERVER_NAME = 0x0000
EXT_SUPPORTED_GROUPS = 0x000A
EXT_SIGNATURE_ALGORITHMS = 0x000D
EXT_ALPN = 0x0010
EXT_PRE_SHARED_KEY = 0x0029
EXT_SUPPORTED_VERSIONS = 0x002B
EXT_PSK_KEY_EXCHANGE_MODES = 0x002D
EXT_KEY_SHARE = 0x0033

# config key -> extension id it needs present in extension_order
CLOSURE = {
    "signature_algorithms": EXT_SIGNATURE_ALGORITHMS,
    "supported_groups": EXT_SUPPORTED_GROUPS,
    "key_share_groups": EXT_KEY_SHARE,
    "supported_versions": EXT_SUPPORTED_VERSIONS,
    "psk_key_exchange_modes": EXT_PSK_KEY_EXCHANGE_MODES,
    "alpn": EXT_ALPN,
}

VERSION_CODES = {0x0304: "13", 0x0303: "12", 0x0302: "11", 0x0301: "10"}


def read_kv(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key.strip()] = value.strip()
    return result


def ints(raw: str) -> list[int]:
    return [int(p) for p in raw.split(",") if p.strip()]


def sha12(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()[:12]


def hex4(value: int) -> str:
    return format(value, "04x")


def alpn_code(alpn: str) -> str:
    """First and last character of the first ALPN value, '00' when absent."""
    if not alpn:
        return "00"
    if ord(alpn[0]) > 127:
        return "99"
    if len(alpn) > 2:
        return alpn[0] + alpn[-1]
    return alpn.ljust(2, "0")


def compute_ja4(conf: dict[str, str]) -> str:
    ciphers = [c for c in ints(conf.get("cipher_suites", "")) if c not in GREASE]
    extensions = [e for e in ints(conf.get("extension_order", "")) if e not in GREASE]
    sigalgs = ints(conf.get("signature_algorithms", ""))

    supported = [v for v in ints(conf.get("supported_versions", "")) if v not in GREASE]
    known = [v for v in supported if v in VERSION_CODES]
    if known:
        version = VERSION_CODES[max(known)]
    else:
        tls_max = int(conf.get("tls_max", "772"))
        version = VERSION_CODES.get(tls_max, "13")

    sni = "i" if conf.get("sni_mode") in ("ip", "none") else "d"

    alpn_list = [a for a in conf.get("alpn", "").split(",") if a]
    alpn = alpn_code(alpn_list[0] if alpn_list else "")

    cipher_hash = (
        sha12(",".join(hex4(c) for c in sorted(ciphers)))
        if ciphers
        else "000000000000"
    )

    # SNI and ALPN are excluded from the extension hash but still counted.
    hashed_exts = sorted(e for e in extensions if e not in (EXT_SERVER_NAME, EXT_ALPN))
    if not hashed_exts and not sigalgs:
        ext_hash = "000000000000"
    else:
        joined = ",".join(hex4(e) for e in hashed_exts)
        if sigalgs:
            joined += "_" + ",".join(hex4(s) for s in sigalgs)
        ext_hash = sha12(joined)

    return (
        f"t{version}{sni}{min(len(ciphers), 99):02d}{min(len(extensions), 99):02d}"
        f"{alpn}_{cipher_hash}_{ext_hash}"
    )


def closure_gaps(conf: dict[str, str]) -> list[int]:
    """Extension ids the stacks would silently append to extension_order."""
    if not conf.get("extension_order"):
        return []
    present = set(ints(conf["extension_order"]))
    missing: list[int] = []
    for key, ext_id in CLOSURE.items():
        if conf.get(key) and ext_id not in present:
            missing.append(ext_id)
    if conf.get("sni_mode") in ("present", "domain") and EXT_SERVER_NAME not in present:
        missing.append(EXT_SERVER_NAME)
    return missing


def insert_closure(order: list[int], missing: list[int]) -> list[int]:
    """Adds ids while keeping pre_shared_key last (RFC 8446 4.2.11)."""
    result = list(order)
    for ext_id in missing:
        if ext_id in result:
            continue
        if EXT_PRE_SHARED_KEY in result:
            result.insert(result.index(EXT_PRE_SHARED_KEY), ext_id)
        else:
            result.append(ext_id)
    return result


def rewrite_value(path: Path, key: str, value: str) -> None:
    lines = path.read_text().splitlines(keepends=True)
    for index, raw in enumerate(lines):
        if raw.strip().startswith(f"{key}="):
            newline = "\n" if raw.endswith("\n") else ""
            lines[index] = f"{key}={value}{newline}"
            path.write_text("".join(lines))
            return
    suffix = "" if not lines or lines[-1].endswith("\n") else "\n"
    path.write_text("".join(lines) + suffix + f"{key}={value}\n")


def check_fixture(name: str, fix: bool) -> list[str]:
    conf_path = FIXTURE_DIR / f"{name}.conf"
    exp_path = FIXTURE_DIR / f"{name}.expected"
    conf = read_kv(conf_path)
    expected = read_kv(exp_path)
    problems: list[str] = []

    # Negative fixtures assert a mismatch bit on purpose; their configs are
    # meant to be broken.
    if "expect_mismatch_bit" in expected:
        return problems

    missing = closure_gaps(conf)
    if missing:
        pretty = ", ".join(f"0x{m:04x}" for m in missing)
        if fix:
            fixed = insert_closure(ints(conf["extension_order"]), missing)
            rewrite_value(conf_path, "extension_order", ",".join(str(v) for v in fixed))
            conf = read_kv(conf_path)
            print(f"  [fix] {name}: extension_order += {pretty}")
        else:
            problems.append(
                f"{name}: extension_order is missing {pretty}, which the patched "
                f"stacks would append silently — the emitted JA4 would not match "
                f"this fixture"
            )

    groups = set(ints(conf.get("supported_groups", "")))
    shares = ints(conf.get("key_share_groups", ""))
    if groups and shares:
        stray = [g for g in shares if g not in groups]
        if stray:
            problems.append(
                f"{name}: key_share_groups {stray} are not in supported_groups "
                f"(RFC 8446 violation, raises invalid_config_combination)"
            )

    recorded = expected.get("expected_ja4", "")
    if recorded and recorded != "auto-baseline":
        computed = compute_ja4(conf)
        if computed != recorded:
            if fix:
                rewrite_value(exp_path, "expected_ja4", computed)
                print(f"  [fix] {name}: expected_ja4 {recorded} -> {computed}")
            else:
                problems.append(
                    f"{name}: expected_ja4={recorded} is not reproducible from "
                    f"{name}.conf (computed {computed})"
                )
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fix",
        action="store_true",
        help="rewrite fixtures so they become self-consistent",
    )
    args = parser.parse_args()

    names = sorted(p.stem for p in FIXTURE_DIR.glob("*.conf"))
    names += sorted(
        f"negative/{p.stem}" for p in (FIXTURE_DIR / "negative").glob("*.conf")
    )

    problems: list[str] = []
    for name in names:
        if not (FIXTURE_DIR / f"{name}.expected").exists():
            problems.append(f"{name}: no .expected file")
            continue
        problems.extend(check_fixture(name, args.fix))

    if problems:
        print("JA4 fixture check FAILED:\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            "\nRun `python3 scripts/ja4_fixture_check.py --fix` to make the "
            "fixtures self-consistent.",
            file=sys.stderr,
        )
        return 1

    print(f"JA4 fixture check OK ({len(names)} fixtures)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
