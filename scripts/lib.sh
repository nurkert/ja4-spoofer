#!/usr/bin/env bash
# Shared helpers for patch management scripts.

source "$(dirname "${BASH_SOURCE[0]}")/lib/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/util.sh"

submodules=(
  "openssl"
  "boringssl"
  "nss"
  "ja4"
  "nginx"
  "ja4-nginx-module"
)

get_upstream_ref() {
  local path="$1"
  local ref
  ref=$(git -C "$path" symbolic-ref -q refs/remotes/origin/HEAD || true)
  if [[ -z "$ref" ]]; then
    echo "origin/master"
  else
    echo "${ref#refs/remotes/}"
  fi
}

get_managed_lib_url() {
  local name="$1"
  local url=""

  if [[ -f "$REPO_ROOT/.gitmodules" ]]; then
    url="$(git config -f "$REPO_ROOT/.gitmodules" --get "submodule.libs/$name.url" || true)"
  fi

  if [[ -n "$url" ]]; then
    printf '%s\n' "$url"
    return 0
  fi

  local manifest="$REPO_ROOT/configs/managed-libs.env"
  load_env_config "$manifest"

  case "$name" in
    openssl) url="${OPENSSL_URL:-}" ;;
    boringssl) url="${BORINGSSL_URL:-}" ;;
    nss) url="${NSS_URL:-}" ;;
    ja4) url="${JA4_URL:-}" ;;
    nginx) url="${NGINX_URL:-}" ;;
    ja4-nginx-module) url="${JA4_NGINX_MODULE_URL:-}" ;;
  esac

  [[ -n "$url" ]] || return 1
  printf '%s\n' "$url"
}

ensure_managed_lib_checkout() {
  local name="$1"
  local path="$2"

  if git -C "$path" rev-parse --git-dir &>/dev/null; then
    return 0
  fi

  local url
  if ! url="$(get_managed_lib_url "$name")"; then
    return 1
  fi

  echo "[info] $name: cloning upstream source into $path"
  mkdir -p "$(dirname "$path")"
  git clone "$url" "$path"
}
