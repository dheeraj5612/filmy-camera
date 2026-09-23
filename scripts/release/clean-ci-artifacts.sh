#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd -P "${script_dir}/../.." && pwd -P)"
ci_dir="${root_dir}/.ci"
retention_days="${FILMY_CI_RETENTION_DAYS:-7}"

[[ "${retention_days}" =~ ^[1-9][0-9]*$ ]] || {
  echo "FILMY_CI_RETENTION_DAYS must be a positive integer" >&2
  exit 64
}
[[ -d "${ci_dir}" && ! -L "${ci_dir}" ]] || exit 0

# Preserve tool caches and source worktrees, even when their timestamps are old.
minimum_mtime_days=$((retention_days - 1))
while IFS= read -r -d '' candidate; do
  case "${candidate##*/}" in
    xcodegen|shellcheck|release-source-*) continue ;;
  esac
  if [[ -e "${candidate}/.git" || -L "${candidate}/.git" || -d "${candidate}/FilmyCamera.xcodeproj" ]]; then
    continue
  fi
  rm -r -- "${candidate}"
done < <(find "${ci_dir}" -mindepth 1 -maxdepth 1 -type d \
  -mtime "+${minimum_mtime_days}" -print0)
