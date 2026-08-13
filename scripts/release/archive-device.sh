#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd -P "${script_dir}/../.." && pwd -P)"
archive_path="${FILMY_ARCHIVE_PATH:-${root_dir}/build/FilmyCamera.xcarchive}"
derived_data_path="${FILMY_DERIVED_DATA_PATH:-${root_dir}/build/DerivedData}"
allow_provisioning_updates=false
asc_key_id="${FILMY_ASC_KEY_ID:-}"
asc_issuer_id="${FILMY_ASC_ISSUER_ID:-}"
asc_key_path="${FILMY_ASC_KEY_PATH:-}"

usage() {
  cat <<'EOF'
Usage:
  scripts/release/archive-device.sh [--allow-provisioning-updates]

Options:
  --allow-provisioning-updates  Explicitly allow Xcode to contact Apple while archiving.

When --allow-provisioning-updates is used, FILMY_ASC_KEY_ID,
FILMY_ASC_ISSUER_ID, and FILMY_ASC_KEY_PATH may also be set to authenticate
headless Xcode provisioning. The private key must be an absolute path outside
the repository; its contents are never printed.
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

canonical_existing_path() {
  local path="$1"
  local directory
  [[ -e "${path}" ]] || return 1
  directory="$(cd -P "$(dirname "${path}")" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "${directory}" "$(basename "${path}")"
}

validate_asc_credentials() {
  local canonical_key_path
  local key_mode
  local key_owner
  local current_user

  [[ "${asc_key_id}" =~ ^[A-Za-z0-9]{10}$ ]] || {
    echo "FILMY_ASC_KEY_ID must be a 10-character App Store Connect key ID" >&2
    exit 64
  }
  [[ "${asc_issuer_id}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || {
    echo "FILMY_ASC_ISSUER_ID must be a UUID" >&2
    exit 64
  }
  [[ "${asc_key_path}" = /* && -f "${asc_key_path}" ]] || {
    echo "FILMY_ASC_KEY_PATH must point to an existing absolute private-key file" >&2
    exit 64
  }
  [[ ! -L "${asc_key_path}" ]] || {
    echo "FILMY_ASC_KEY_PATH must not be a symlink" >&2
    exit 64
  }
  canonical_key_path="$(canonical_existing_path "${asc_key_path}")" || {
    echo "FILMY_ASC_KEY_PATH could not be canonicalized" >&2
    exit 64
  }
  case "${canonical_key_path}/" in
    "${root_dir}/"*)
      echo "FILMY_ASC_KEY_PATH must point outside the repository" >&2
      exit 64
      ;;
  esac

  key_mode="$(stat -f '%Lp' "${canonical_key_path}" 2>/dev/null || true)"
  [[ "${key_mode}" =~ ^[0-7]{3,4}$ && "${key_mode: -2}" == 00 ]] || {
    echo "FILMY_ASC_KEY_PATH must not be group- or world-readable" >&2
    exit 64
  }
  current_user="$(id -un 2>/dev/null || true)"
  key_owner="$(stat -f '%Su' "${canonical_key_path}" 2>/dev/null || true)"
  [[ -n "${current_user}" && "${key_owner}" == "${current_user}" ]] || {
    echo "FILMY_ASC_KEY_PATH must be owned by the current user" >&2
    exit 64
  }
  command -v openssl >/dev/null 2>&1 && openssl pkey -in "${canonical_key_path}" -noout -passin pass: >/dev/null 2>&1 || {
    echo "FILMY_ASC_KEY_PATH must be a readable unencrypted private key" >&2
    exit 64
  }

  asc_key_path="${canonical_key_path}"
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
  if [[ -n "${asc_key_id}${asc_issuer_id}${asc_key_path}" ]]; then
    [[ -n "${asc_key_id}" && -n "${asc_issuer_id}" && -n "${asc_key_path}" ]] || {
      echo "FILMY_ASC_KEY_ID, FILMY_ASC_ISSUER_ID, and FILMY_ASC_KEY_PATH must be provided together" >&2
      exit 64
    }
    validate_asc_credentials
    archive_args+=(
      -authenticationKeyIssuerID "${asc_issuer_id}"
      -authenticationKeyID "${asc_key_id}"
      -authenticationKeyPath "${asc_key_path}"
    )
  fi
fi

archive_args+=( archive )
xcodebuild "${archive_args[@]}"

"${script_dir}/validate-archive.sh" "${archive_path}"
