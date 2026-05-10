#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
include_wip=0

usage() {
  cat <<'USAGE'
Usage: scripts/refresh_patches.sh [--include-wip]

  --include-wip   Also export uncommitted submodule diffs as *.diff files
                  into patches/<lib>/ (working tree + staged/index).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-wip)
      include_wip=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[error] unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

for name in "${submodules[@]}"; do
  sub_path="$repo_root/libs/$name"
  patch_dir="$repo_root/patches/$name"

  if ! git -C "$sub_path" rev-parse --git-dir &>/dev/null; then
    echo "[skip] $name: submodule not initialized at $sub_path" >&2
    continue
  fi

  upstream_ref=$(get_upstream_ref "$sub_path")

  mkdir -p "$patch_dir"
  rm -f "$patch_dir"/*.patch
  if [[ "$include_wip" -eq 1 ]]; then
    rm -f "$patch_dir"/*.diff
  fi

  echo "[info] $name: exporting patches from $upstream_ref..HEAD"
  git -C "$sub_path" format-patch -o "$patch_dir" "$upstream_ref"..HEAD >/dev/null

  if ls "$patch_dir"/*.patch >/dev/null 2>&1; then
    echo "[ok]  $name: wrote patches to $patch_dir"
  else
    echo "[ok]  $name: no local commits to export"
  fi

  if [[ "$include_wip" -eq 1 ]]; then
    worktree_diff="$patch_dir/9998-wip-working-tree.diff"
    staged_diff="$patch_dir/9999-wip-index.diff"

    git -C "$sub_path" diff > "$worktree_diff"
    git -C "$sub_path" diff --cached > "$staged_diff"

    if [[ ! -s "$worktree_diff" ]]; then
      rm -f "$worktree_diff"
    fi
    if [[ ! -s "$staged_diff" ]]; then
      rm -f "$staged_diff"
    fi

    if ls "$patch_dir"/*.diff >/dev/null 2>&1; then
      echo "[ok]  $name: wrote wip diffs to $patch_dir"
    else
      echo "[ok]  $name: no wip diffs to export"
    fi
  fi

done
