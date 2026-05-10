#!/usr/bin/env bash
# Process management: find and handle existing browser processes.

find_pids_for_binary() {
  local binary_path="$1"
  local line pid cmd

  while IFS= read -r line; do
    pid="${line%% *}"
    cmd="${line#* }"
    [[ -z "$pid" ]] && continue
    if [[ "$cmd" == *"$binary_path"* ]]; then
      printf '%s\n' "$pid"
    fi
  done < <(ps -axo pid=,command=)
}

handle_existing_processes() {
  local binary_path="$1"
  local browser_name="$2"
  local kill_existing="$3"
  local allow_existing="$4"
  local dry_run="$5"

  local -a existing_pids
  mapfile -t existing_pids < <(find_pids_for_binary "$binary_path" || true)

  if [[ "${#existing_pids[@]}" -eq 0 ]]; then
    return 0
  fi

  if [[ "$kill_existing" -eq 1 ]]; then
    if [[ "$dry_run" -eq 1 ]]; then
      echo "[dry-run] would kill existing $browser_name processes for same binary: ${existing_pids[*]}"
    else
      echo "[info] killing existing $browser_name processes for same binary: ${existing_pids[*]}"
      kill "${existing_pids[@]}" >/dev/null 2>&1 || true
      sleep 1
      mapfile -t existing_pids < <(find_pids_for_binary "$binary_path" || true)
      if [[ "${#existing_pids[@]}" -gt 0 ]]; then
        kill -9 "${existing_pids[@]}" >/dev/null 2>&1 || true
        sleep 1
      fi
    fi
  elif [[ "$allow_existing" -eq 1 ]]; then
    echo "[warn] existing $browser_name process detected for same binary; JA4 config may not apply to an already-running process."
  else
    echo "[error] existing $browser_name process detected for same binary: ${existing_pids[*]}" >&2
    echo "[hint] close it first, or rerun with --kill-existing (recommended) or --allow-existing." >&2
    exit 1
  fi
}
