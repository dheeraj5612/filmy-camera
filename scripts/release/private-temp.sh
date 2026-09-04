#!/usr/bin/env bash

# Source from release entrypoints. Call new_temp_file/new_temp_dir directly
# with an output variable, never through $(...), so the EXIT trap owns every
# artifact, including any staged signing key, in the calling shell.
filmy_temp_paths=()

cleanup_private_temps() {
  local filmy_temp_path
  if [[ "${#filmy_temp_paths[@]}" -gt 0 ]]; then
    for filmy_temp_path in "${filmy_temp_paths[@]}"; do
      [[ -n "${filmy_temp_path}" ]] && rm -rf -- "${filmy_temp_path}"
    done
  fi
}
trap cleanup_private_temps EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

new_temp_file() {
  local filmy_created_path
  [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 64
  filmy_created_path="$(mktemp -t filmycamera-release)" || return
  filmy_temp_paths+=("${filmy_created_path}")
  printf -v "$1" '%s' "${filmy_created_path}"
}

new_temp_dir() {
  local filmy_created_path
  [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 64
  filmy_created_path="$(mktemp -d -t filmycamera-release)" || return
  filmy_temp_paths+=("${filmy_created_path}")
  printf -v "$1" '%s' "${filmy_created_path}"
}
