#!/usr/bin/env python3
"""Regenerate platform launcher/window icons from assets/icon.png.

The Flutter `flutter_launcher_icons` package does not actually generate Linux
icons, so without this helper `linux/runner/resources/app_icon.png` (used by
the GTK runner for the window/taskbar icon) silently drifts away from
`assets/icon.png`. The packaging step calls this script so the bundled icon
always matches the canonical source.

Usage:
  scripts/sync_app_icon.py [--source <path>] [--check]

The script targets the Linux runner resource by default; macOS and Windows
already have working flutter_launcher_icons pipelines and are left alone.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ModuleNotFoundError:
    sys.stderr.write(
        "[error] Pillow (PIL) is required — install with `pip install pillow` "
        "or `apt install python3-pil`\n"
    )
    sys.exit(1)


def _resolve_project_root() -> Path:
    # scripts/sync_app_icon.py lives at <repo>/tools/ja4-spoofer/scripts/.
    return Path(__file__).resolve().parents[1]


# (relative path inside tools/ja4-spoofer, target square size in px)
_LINUX_TARGETS: tuple[tuple[str, int], ...] = (
    ("linux/runner/resources/app_icon.png", 256),
)


def _resize(src: Path, dst: Path, size: int) -> bool:
    """Return True if dst was written (i.e. content changed)."""
    with Image.open(src) as img:
        img = img.convert("RGBA")
        resized = img.resize((size, size), Image.LANCZOS)
        dst.parent.mkdir(parents=True, exist_ok=True)
        # Write to a temp file and compare bytes so unchanged builds stay
        # reproducible and CMake doesn't re-link on every run.
        tmp = dst.with_suffix(dst.suffix + ".tmp")
        resized.save(tmp, format="PNG", optimize=True)
        new_bytes = tmp.read_bytes()
        if dst.exists() and dst.read_bytes() == new_bytes:
            tmp.unlink()
            return False
        tmp.replace(dst)
        return True


def main() -> int:
    project_root = _resolve_project_root()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        default=str(project_root / "assets" / "icon.png"),
        help="canonical source PNG (default: assets/icon.png)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero if any target would be regenerated",
    )
    args = parser.parse_args()

    src = Path(args.source).resolve()
    if not src.is_file():
        sys.stderr.write(f"[error] source icon not found: {src}\n")
        return 1

    drift = False
    for rel, size in _LINUX_TARGETS:
        dst = project_root / rel
        changed = _resize(src, dst, size)
        if changed:
            print(f"[info] regenerated {rel} ({size}x{size})")
            drift = True
        else:
            print(f"[ok]   {rel} already in sync")

    if args.check and drift:
        sys.stderr.write(
            "[error] platform icons drifted from assets/icon.png — "
            "run scripts/sync_app_icon.py to regenerate\n"
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
