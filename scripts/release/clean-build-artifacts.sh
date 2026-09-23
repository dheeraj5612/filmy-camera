#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd -P "${script_dir}/../.." && pwd -P)"

# Build output is disposable. Keep the cleanup narrowly scoped to the derived
# data directory owned by the release workflow, and refuse unexpected paths.
[[ "$#" -eq 1 ]] || {
  echo "Usage: $0 DERIVED_DATA_PATH" >&2
  exit 64
}
derived_data_path="$1"
case "${derived_data_path}" in
  "${root_dir}/build/DerivedData"|"${root_dir}/build/DerivedData-G7Camera") ;;
  *)
    echo "Refusing to clean unexpected derived-data path: ${derived_data_path}" >&2
    exit 64
    ;;
esac

build_path="${root_dir}/build"
[[ -d "${build_path}" ]] || {
  echo "Build directory is missing: ${build_path}" >&2
  exit 64
}
build_realpath="$(cd -P "${build_path}" && pwd -P)" || {
  echo "Unable to resolve build directory: ${build_path}" >&2
  exit 64
}
if [[ "${build_realpath}" != "${root_dir}/build" && "${build_realpath}" != */Documents/ChatGPT/filmyCamera/build ]]; then
  echo "Refusing to clean untrusted build target: ${build_realpath}" >&2
  exit 64
fi

expected_derived_path="${build_realpath}/$(basename "${derived_data_path}")"
resolved_parent="$(cd -P "$(dirname "${derived_data_path}")" 2>/dev/null && pwd -P)" || {
  echo "Unable to resolve derived-data parent: ${derived_data_path}" >&2
  exit 64
}
[[ "${resolved_parent}/${expected_derived_path##*/}" == "${expected_derived_path}" ]] || {
  echo "Derived-data path escapes the trusted build directory: ${derived_data_path}" >&2
  exit 64
}
if [[ -L "${derived_data_path}" ]]; then
  echo "Refusing to clean a symlinked derived-data path: ${derived_data_path}" >&2
  exit 64
fi

if [[ -e "${derived_data_path}" && ! -d "${derived_data_path}" ]]; then
  echo "Derived-data path is not a directory: ${derived_data_path}" >&2
  exit 64
fi

if [[ -d "${derived_data_path}" ]]; then
  find "${derived_data_path}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
fi

echo "Cleared disposable derived data: ${derived_data_path}"
