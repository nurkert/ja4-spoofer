#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
with_wip=0

filter_sub=""

usage() {
  cat <<'USAGE'
Usage: scripts/apply_patches.sh [--with-wip] [--only <submodule>]

  --with-wip          Also apply *.diff files from patches/<lib>/ after git-am patches.
  --only <submodule>  Only patch the given submodule (e.g. nss, openssl, boringssl).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-wip)
      with_wip=1
      ;;
    --only)
      shift
      filter_sub="${1:-}"
      if [[ -z "$filter_sub" ]]; then
        echo "[error] --only requires a submodule name" >&2
        exit 1
      fi
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
  if [[ -n "$filter_sub" && "$name" != "$filter_sub" ]]; then
    continue
  fi

  sub_path="$repo_root/libs/$name"
  patch_dir="$repo_root/patches/$name"

  if ! git -C "$sub_path" rev-parse --git-dir &>/dev/null; then
    if [[ -n "$filter_sub" ]]; then
      echo "[info] $name: source checkout missing"
      if git -C "$repo_root" rev-parse --show-toplevel &>/dev/null; then
        echo "[info] $name: initializing git submodule"
        git -C "$repo_root" submodule update --init "libs/$name"
      else
        ensure_managed_lib_checkout "$name" "$sub_path"
      fi
    else
      echo "[skip] $name: submodule not initialized at $sub_path" >&2
      continue
    fi
  fi

  if [[ ! -d "$patch_dir" ]]; then
    echo "[skip] $name: no patches directory at $patch_dir" >&2
    continue
  fi

  base_ref_file="$patch_dir/BASE_REF"
  if [[ -f "$base_ref_file" ]]; then
    upstream_ref=$(tr -d '[:space:]' < "$base_ref_file")
  else
    upstream_ref=$(get_upstream_ref "$sub_path")
  fi

  echo "[info] $name: fetching upstream"
  git -C "$sub_path" fetch origin >/dev/null

  echo "[info] $name: checking out $upstream_ref"
  git -C "$sub_path" checkout -q "$upstream_ref"
  git -C "$sub_path" checkout -B my-changes >/dev/null

  if ls "$patch_dir"/*.patch >/dev/null 2>&1; then
    echo "[info] $name: applying patches"
    git -C "$sub_path" -c commit.gpgsign=false am "$patch_dir"/*.patch >/dev/null
    echo "[ok]  $name: patches applied"
  else
    echo "[ok]  $name: no patches to apply"
  fi

  if [[ "$with_wip" -eq 1 ]]; then
    if ls "$patch_dir"/*.diff >/dev/null 2>&1; then
      echo "[info] $name: applying wip diffs"
      for diff_file in "$patch_dir"/*.diff; do
        git -C "$sub_path" apply "$diff_file"
      done
      echo "[ok]  $name: wip diffs applied"
    else
      echo "[ok]  $name: no wip diffs to apply"
    fi
  fi

done
