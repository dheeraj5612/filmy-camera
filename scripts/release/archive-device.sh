#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/../.." && pwd)"
archive_path="${FILMY_ARCHIVE_PATH:-${root_dir}/build/FilmyCamera.xcarchive}"
derived_data_path="${FILMY_DERIVED_DATA_PATH:-${root_dir}/build/DerivedData}"
allow_provisioning_updates=false

usage() {
  cat <<'EOF'
Usage:
  scripts/release/archive-device.sh [--allow-provisioning-updates]

Options:
  --allow-provisioning-updates  Explicitly allow Xcode to contact Apple while archiving.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --allow-provisioning-updates)
      allow_provisioning_updates=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

command -v xcodegen >/dev/null || {
  echo "xcodegen is required; install it with: brew install xcodegen" >&2
  exit 127
}

mkdir -p "$(dirname "${archive_path}")" "${derived_data_path}"
xcodegen generate --spec "${root_dir}/project.yml"

archive_args=(
  -project "${root_dir}/FilmyCamera.xcodeproj"
  -scheme FilmyCamera
  -configuration Release
  -destination 'generic/platform=iOS'
  -derivedDataPath "${derived_data_path}"
  -archivePath "${archive_path}"
)
if [[ "${allow_provisioning_updates}" == true ]]; then
  archive_args+=( -allowProvisioningUpdates )
fi

archive_args+=( archive )
xcodebuild "${archive_args[@]}"

"${script_dir}/validate-archive.sh" "${archive_path}"
