#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d -t filmycamera-cleanup-test)"
trap 'rm -rf -- "${test_root}"' EXIT

# Exercise actual process exit and signal handling with disposable sentinel
# data. No signing material or Apple connection is needed for this test.
for exit_mode in success failure signal; do
  manifest="${test_root}/${exit_mode}.txt"
  set +e
  bash -c '
    set -euo pipefail
    source "$1/private-temp.sh"
    allocate_from_function() {
      local staged_file staged_directory
      new_temp_file staged_file
      new_temp_dir staged_directory
      mkdir -m 700 "${staged_directory}/private_keys"
      printf "disposable sentinel" > "${staged_directory}/private_keys/sentinel.txt"
      printf "%s\n%s\n" "${staged_file}" "${staged_directory}" > "$2"
    }
    allocate_from_function "$@"
    case "$3" in
      success) exit 0 ;;
      failure) exit 31 ;;
      signal) kill -TERM "$$"; exit 99 ;;
    esac
  ' bash "${script_dir}" "${manifest}" "${exit_mode}"
  exit_status="$?"
  set -e
  case "${exit_mode}" in
    success) [[ "${exit_status}" -eq 0 ]] ;;
    failure) [[ "${exit_status}" -eq 31 ]] ;;
    signal) [[ "${exit_status}" -eq 143 ]] ;;
  esac
  [[ -s "${manifest}" ]]
  while IFS= read -r artifact; do
    [[ ! -e "${artifact}" ]] || {
      echo "Release temporary data survived ${exit_mode}" >&2
      exit 1
    }
  done < "${manifest}"
done
echo "Release temporary data cleanup passed (success, failure, signal)"
