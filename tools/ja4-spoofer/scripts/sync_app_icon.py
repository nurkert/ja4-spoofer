#!/usr/bin/env python3
"""Regenerate platform launcher/window icons from assets/icon.png.

The Flutter `flutter_launcher_icons` package does not generate Linux icons,
so without this helper:

  * `linux/runner/resources/app_icon.png` (used by the GTK runner for the
    in-window/titlebar icon) silently drifts from `assets/icon.png`.
  * The `.deb` ships a single oversized PNG under `hicolor/256x256/apps/`,
    which most desktops (GNOME, Cinnamon, KDE) treat as broken: directories
    in the hicolor theme are *expected* to contain icons matching their
    declared size, otherwise the lookup either falls back to the generic
    placeholder or scales poorly.

This script handles both cases:

  scripts/sync_app_icon.py                # regenerate the runner icon
  scripts/sync_app_icon.py \
      --hicolor-out <stage>/usr/share/icons/hicolor
                                          # populate every hicolor size
                                          # bucket used by the .deb

`--check` exits non-zero if any target would change (useful as a CI guard).
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
_LINUX_RUNNER_TARGETS: tuple[tuple[str, int], ...] = (
    ("linux/runner/resources/app_icon.png", 256),
)

# Hicolor sizes shipped in the .deb. 16/32 cover small widget chrome,
# 48/64 cover panel/taskbar slots, 128/256 cover Activities/Alt-Tab,
# 512 is what GNOME uses for the Software/Files preview.
_HICOLOR_SIZES: tuple[int, ...] = (16, 32, 48, 64, 128, 256, 512)


def _resize(src: Path, dst: Path, size: int) -> bool:
    """Resize src to a square `size`px image. Returns True if dst changed."""
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


def _sync_runner_icons(project_root: Path, src: Path) -> bool:
    drift = False
    for rel, size in _LINUX_RUNNER_TARGETS:
        dst = project_root / rel
        if _resize(src, dst, size):
            print(f"[info] regenerated {rel} ({size}x{size})")
            drift = True
        else:
            print(f"[ok]   {rel} already in sync")
    return drift


def _sync_hicolor(src: Path, hicolor_root: Path, icon_name: str) -> bool:
    """Populate hicolor/<size>x<size>/apps/<icon_name>.png for every size."""
    drift = False
    for size in _HICOLOR_SIZES:
        dst = hicolor_root / f"{size}x{size}" / "apps" / f"{icon_name}.png"
        if _resize(src, dst, size):
            print(f"[info] regenerated hicolor/{size}x{size}/apps/{icon_name}.png")
            drift = True
        else:
            print(f"[ok]   hicolor/{size}x{size}/apps/{icon_name}.png in sync")
    return drift


def main() -> int:
    project_root = _resolve_project_root()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        default=str(project_root / "assets" / "icon.png"),
        help="canonical source PNG (default: assets/icon.png)",
    )
    parser.add_argument(
        "--hicolor-out",
        default=None,
        help=(
            "If set, also write hicolor/<size>x<size>/apps/<icon-name>.png "
            "under this directory (typically the .deb staging "
            "<root>/usr/share/icons/hicolor)."
        ),
    )
    parser.add_argument(
        "--icon-name",
        default="ja4-spoofer",
        help="basename used for hicolor entries (default: ja4-spoofer)",
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

    drift = _sync_runner_icons(project_root, src)

    if args.hicolor_out is not None:
        hicolor_root = Path(args.hicolor_out).resolve()
        drift = _sync_hicolor(src, hicolor_root, args.icon_name) or drift

    if args.check and drift:
        sys.stderr.write(
            "[error] platform icons drifted from assets/icon.png — "
            "run scripts/sync_app_icon.py to regenerate\n"
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
