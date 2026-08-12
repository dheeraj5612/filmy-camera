#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/../.." && pwd)"
archive_path="${FILMY_ARCHIVE_PATH:-${root_dir}/build/FilmyCamera.xcarchive}"
derived_data_path="${FILMY_DERIVED_DATA_PATH:-${root_dir}/build/DerivedData}"

command -v xcodegen >/dev/null || {
  echo "xcodegen is required; install it with: brew install xcodegen" >&2
  exit 127
}

mkdir -p "$(dirname "${archive_path}")" "${derived_data_path}"
xcodegen generate --spec "${root_dir}/project.yml"

xcodebuild \
  -project "${root_dir}/FilmyCamera.xcodeproj" \
  -scheme FilmyCamera \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "${derived_data_path}" \
  -archivePath "${archive_path}" \
  -allowProvisioningUpdates \
  archive

"${script_dir}/validate-archive.sh" "${archive_path}"
