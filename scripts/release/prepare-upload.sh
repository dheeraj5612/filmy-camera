#!/usr/bin/env bash
set -euo pipefail

# This script deliberately does not enable provisioning updates or upload by
# default. API keys are accepted only by path, are required to live outside
# the repository, and are copied to a short-lived private_keys directory only
# for the Transporter invocation.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/../.." && pwd)"
bundle_id="com.dheeraj.filmycamera"
project_spec="${root_dir}/project.yml"
team_id="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM:[[:space:]]*\([^[:space:]]*\)[[:space:]]*$/\1/p' "${project_spec}" | head -n 1)"

archive_path="${FILMY_ARCHIVE_PATH:-${root_dir}/build/FilmyCamera.xcarchive}"
export_path="${FILMY_EXPORT_PATH:-${root_dir}/build/export}"
asc_key_id="${FILMY_ASC_KEY_ID:-}"
asc_issuer_id="${FILMY_ASC_ISSUER_ID:-}"
asc_key_path="${FILMY_ASC_KEY_PATH:-}"
mode="check"
mode_was_set=false
allow_provisioning_updates=false
ipa_path=""
temp_paths=()

cleanup() {
  local path
  if [[ "${#temp_paths[@]}" -gt 0 ]]; then
    for path in "${temp_paths[@]}"; do
      [[ -n "${path}" ]] && rm -rf "${path}"
    done
  fi
}
trap cleanup EXIT HUP INT TERM

die() {
  echo "Release preparation error: $*" >&2
  exit 64
}

usage() {
  cat <<'EOF'
Usage:
  scripts/release/prepare-upload.sh [--check]
  scripts/release/prepare-upload.sh --export [options]
  scripts/release/prepare-upload.sh --upload [options]

Modes:
  --check                         No-export readiness check (default).
  --export                        Validate an archive and export an IPA locally.
  --upload                        Export an IPA, then upload it with Transporter.

Options:
  --archive PATH                  Release archive (default: build/FilmyCamera.xcarchive).
  --export-path PATH              Empty export directory (default: build/export).
  --allow-provisioning-updates    Explicitly allow Xcode to contact Apple during export.
  -h, --help                      Show this help.

Upload credentials are read only from these environment variables:
  FILMY_ASC_KEY_ID
  FILMY_ASC_ISSUER_ID
  FILMY_ASC_KEY_PATH               An unencrypted .p8 file outside this repository.

No credential values are printed. --check never exports, contacts Apple, or uploads.
EOF
}

set_mode() {
  local requested_mode="$1"
  if [[ "${mode_was_set}" == true && "${mode}" != "${requested_mode}" ]]; then
    die "choose exactly one of --check, --export, or --upload"
  fi
  mode="${requested_mode}"
  mode_was_set=true
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --check)
      set_mode check
      shift
      ;;
    --export)
      set_mode export
      shift
      ;;
    --upload)
      set_mode upload
      shift
      ;;
    --archive)
      [[ "$#" -ge 2 ]] || die "--archive requires a path"
      archive_path="$2"
      shift 2
      ;;
    --export-path)
      [[ "$#" -ge 2 ]] || die "--export-path requires a path"
      export_path="$2"
      shift 2
      ;;
    --allow-provisioning-updates)
      allow_provisioning_updates=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1 (use --help for usage)"
      ;;
  esac
done

[[ "${archive_path}" = /* ]] || archive_path="${root_dir}/${archive_path}"
[[ "${export_path}" = /* ]] || export_path="${root_dir}/${export_path}"

if [[ -n "${asc_key_path}" && "${asc_key_path}" != /* ]]; then
  asc_key_path="${root_dir}/${asc_key_path}"
fi

if [[ "${mode}" == check && "${allow_provisioning_updates}" == true ]]; then
  die "--allow-provisioning-updates is only valid with --export or --upload"
fi

new_temp_file() {
  local path
  path="$(mktemp -t filmycamera-release)"
  temp_paths+=("${path}")
  printf '%s\n' "${path}"
}

new_temp_dir() {
  local path
  path="$(mktemp -d -t filmycamera-release)"
  temp_paths+=("${path}")
  printf '%s\n' "${path}"
}

canonical_existing_path() {
  local path="$1"
  local directory
  [[ -e "${path}" ]] || return 1
  directory="$(cd -P "$(dirname "${path}")" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "${directory}" "$(basename "${path}")"
}

path_is_inside_repository() {
  local path="$1"
  case "${path}/" in
    "${root_dir}/"*) return 0 ;;
    *) return 1 ;;
  esac
}

plist_value() {
  local key="$1"
  local plist_path="$2"
  /usr/libexec/PlistBuddy -c "Print :${key}" "${plist_path}" 2>/dev/null
}

run_project_preflight() {
  "${script_dir}/validate-project.sh"
}

run_store_metadata_preflight() {
  "${script_dir}/validate-store-metadata.sh" --final
}

has_distribution_identity() {
  local identities
  command -v security >/dev/null 2>&1 || return 1
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  grep -Eq '"(Apple Distribution|iPhone Distribution):' <<<"${identities}"
}

has_installed_app_store_profile() {
  local user_home="${HOME:-}"
  local profile_dir
  local profile_path
  local decoded_profile
  local application_identifier
  local get_task_allow
  local expiration_date
  local expiration_epoch

  [[ -n "${user_home}" ]] || return 1
  command -v security >/dev/null 2>&1 || return 1
  profile_dir="${user_home}/Library/MobileDevice/Provisioning Profiles"
  [[ -d "${profile_dir}" ]] || return 1
  decoded_profile="$(new_temp_file)"

  for profile_path in "${profile_dir}"/*.mobileprovision "${profile_dir}"/*.provisionprofile; do
    [[ -f "${profile_path}" ]] || continue
    if ! security cms -D -i "${profile_path}" -o "${decoded_profile}" 2>/dev/null; then
      continue
    fi
    application_identifier="$(plist_value 'Entitlements:application-identifier' "${decoded_profile}" 2>/dev/null || true)"
    get_task_allow="$(plist_value 'Entitlements:get-task-allow' "${decoded_profile}" 2>/dev/null || true)"
    expiration_date="$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "${decoded_profile}" 2>/dev/null || true)"
    expiration_epoch="$(date -j -f '%Y-%m-%d %H:%M:%S %z' "${expiration_date}" '+%s' 2>/dev/null || true)"
    [[ "${application_identifier}" == "${team_id}.${bundle_id}" ]] || continue
    [[ "${get_task_allow}" == false ]] || continue
    [[ -n "${expiration_epoch}" && "${expiration_epoch}" -gt "$(date '+%s')" ]] || continue
    # App Store profiles do not contain a ProvisionedDevices entitlement.
    if /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "${decoded_profile}" >/dev/null 2>&1; then
      continue
    fi
    return 0
  done

  return 1
}

validate_asc_credentials() {
  local failures=0
  local key_mode
  local key_owner
  local current_user
  local canonical_key_path

  if [[ -z "${asc_key_id}" ]]; then
    echo "Missing App Store Connect API key ID: set FILMY_ASC_KEY_ID" >&2
    failures=1
  elif [[ ! "${asc_key_id}" =~ ^[A-Za-z0-9]{10}$ ]]; then
    echo "Invalid App Store Connect API key ID format" >&2
    failures=1
  fi

  if [[ -z "${asc_issuer_id}" ]]; then
    echo "Missing App Store Connect issuer ID: set FILMY_ASC_ISSUER_ID" >&2
    failures=1
  elif [[ ! "${asc_issuer_id}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
    echo "Invalid App Store Connect issuer ID format" >&2
    failures=1
  fi

  if [[ -z "${asc_key_path}" ]]; then
    echo "Missing App Store Connect private key path: set FILMY_ASC_KEY_PATH" >&2
    failures=1
  elif ! canonical_key_path="$(canonical_existing_path "${asc_key_path}")"; then
    echo "App Store Connect private key file was not found" >&2
    failures=1
  else
    asc_key_path="${canonical_key_path}"
    if [[ -L "${asc_key_path}" ]]; then
      echo "App Store Connect private key must not be a symlink" >&2
      failures=1
    fi
    if path_is_inside_repository "${asc_key_path}"; then
      echo "App Store Connect private key must be outside the repository" >&2
      failures=1
    fi
    key_mode="$(stat -f '%Lp' "${asc_key_path}" 2>/dev/null || true)"
    if [[ ! "${key_mode}" =~ ^[0-7]{3,4}$ || "${key_mode: -2}" != 00 ]]; then
      echo "App Store Connect private key must not be group- or world-readable" >&2
      failures=1
    fi
    current_user="$(id -un 2>/dev/null || true)"
    key_owner="$(stat -f '%Su' "${asc_key_path}" 2>/dev/null || true)"
    if [[ -n "${current_user}" && "${key_owner}" != "${current_user}" ]]; then
      echo "App Store Connect private key must be owned by the current user" >&2
      failures=1
    fi
    if ! command -v openssl >/dev/null 2>&1 || ! openssl pkey -in "${asc_key_path}" -noout -passin pass: >/dev/null 2>&1; then
      echo "App Store Connect private key is not a readable unencrypted private key" >&2
      failures=1
    fi
  fi

  [[ "${failures}" -eq 0 ]]
}

require_local_distribution_material() {
  local failures=0

  if ! has_distribution_identity; then
    echo "Missing Apple Distribution certificate in the current keychain" >&2
    failures=1
  fi
  if ! has_installed_app_store_profile; then
    echo "Missing App Store provisioning profile for the production bundle" >&2
    failures=1
  fi

  [[ "${failures}" -eq 0 ]]
}

validate_archive() {
  [[ -d "${archive_path}" ]] || {
    echo "Release archive not found; run scripts/release/archive-device.sh first" >&2
    return 1
  }
  "${script_dir}/validate-archive.sh" "${archive_path}"
}

ensure_empty_export_path() {
  local existing_entry
  if [[ -e "${export_path}" && ! -d "${export_path}" ]]; then
    echo "Export path is not a directory" >&2
    return 1
  fi
  if [[ -d "${export_path}" ]]; then
    existing_entry="$(find "${export_path}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)"
    if [[ -n "${existing_entry}" ]]; then
      echo "Export path must be empty; refusing to overwrite existing files" >&2
      return 1
    fi
  else
    mkdir -p "${export_path}"
  fi
}

validate_exported_ipa() {
  local ipa="$1"
  local archive_app_path="${archive_path}/Products/Applications/FilmyCamera.app"
  local archive_info_plist="${archive_app_path}/Info.plist"
  local ipa_work_dir
  local ipa_app_path
  local ipa_info_plist
  local decoded_profile
  local archive_version
  local archive_build
  local ipa_version
  local ipa_build
  local application_identifier
  local profile_bundle_id
  local profile_team_id
  local get_task_allow
  local expiration_date
  local expiration_epoch
  local signature_details

  [[ -f "${ipa}" ]] || {
    echo "Xcode export did not produce FilmyCamera.ipa" >&2
    return 1
  }
  command -v unzip >/dev/null 2>&1 || {
    echo "unzip is required to validate the exported IPA" >&2
    return 127
  }
  command -v codesign >/dev/null 2>&1 || {
    echo "codesign is required to validate the exported IPA" >&2
    return 127
  }
  command -v security >/dev/null 2>&1 || {
    echo "The macOS security tool is required to validate the exported IPA" >&2
    return 127
  }

  ipa_work_dir="$(new_temp_dir)"
  unzip -qq "${ipa}" -d "${ipa_work_dir}" >/dev/null 2>&1 || {
    echo "Exported IPA is not a valid ZIP archive" >&2
    return 1
  }
  ipa_app_path="${ipa_work_dir}/Payload/FilmyCamera.app"
  ipa_info_plist="${ipa_app_path}/Info.plist"
  if [[ ! -d "${ipa_app_path}" || ! -f "${ipa_info_plist}" ]]; then
    echo "Exported IPA does not contain FilmyCamera.app" >&2
    return 1
  fi

  archive_version="$(plist_value CFBundleShortVersionString "${archive_info_plist}")"
  archive_build="$(plist_value CFBundleVersion "${archive_info_plist}")"
  ipa_version="$(plist_value CFBundleShortVersionString "${ipa_info_plist}")"
  ipa_build="$(plist_value CFBundleVersion "${ipa_info_plist}")"
  if [[ "$(plist_value CFBundleIdentifier "${ipa_info_plist}")" != "${bundle_id}" \
    || "${ipa_version}" != "${archive_version}" \
    || "${ipa_build}" != "${archive_build}" ]]; then
    echo "Exported IPA metadata does not match the validated archive" >&2
    return 1
  fi

  [[ -f "${ipa_app_path}/embedded.mobileprovision" ]] || {
    echo "Exported IPA has no embedded provisioning profile" >&2
    return 1
  }
  decoded_profile="$(new_temp_file)"
  security cms -D -i "${ipa_app_path}/embedded.mobileprovision" -o "${decoded_profile}" 2>/dev/null || {
    echo "Unable to decode the exported IPA provisioning profile" >&2
    return 1
  }
  application_identifier="$(plist_value 'Entitlements:application-identifier' "${decoded_profile}" 2>/dev/null || true)"
  profile_team_id="${application_identifier%%.*}"
  profile_bundle_id="${application_identifier#*.}"
  get_task_allow="$(plist_value 'Entitlements:get-task-allow' "${decoded_profile}" 2>/dev/null || true)"
  expiration_date="$(plist_value ExpirationDate "${decoded_profile}" 2>/dev/null || true)"
  expiration_epoch="$(date -j -f '%Y-%m-%d %H:%M:%S %z' "${expiration_date}" '+%s' 2>/dev/null || true)"
  [[ "${profile_team_id}" == "${team_id}" && "${profile_bundle_id}" == "${bundle_id}" ]] || {
    echo "Exported IPA provisioning profile does not match the production app" >&2
    return 1
  }
  [[ "${get_task_allow}" == false ]] || {
    echo "Exported IPA must disable get-task-allow" >&2
    return 1
  }
  [[ -n "${expiration_epoch}" && "${expiration_epoch}" -gt "$(date '+%s')" ]] || {
    echo "Exported IPA provisioning profile is expired or has an unreadable expiration date" >&2
    return 1
  }

  signature_details="$(codesign -dv --verbose=4 "${ipa_app_path}" 2>&1 || true)"
  if ! codesign --verify --deep --strict --verbose=2 "${ipa_app_path}" >/dev/null 2>&1; then
    echo "Exported IPA app signature failed verification" >&2
    return 1
  fi
  if ! grep -Eq '^Authority=(Apple Distribution|iPhone Distribution):' <<<"${signature_details}"; then
    echo "Exported IPA is not signed for App Store distribution" >&2
    return 1
  fi
}

write_export_options() {
  local export_options_path="$1"
  cat >"${export_options_path}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${team_id}</string>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
EOF
}

prepare_export() {
  local export_options_path
  local export_log
  local export_status
  local exporter_args=()

  run_project_preflight
  run_store_metadata_preflight
  validate_archive
  require_local_distribution_material
  ensure_empty_export_path

  export_options_path="$(new_temp_file)"
  export_log="$(new_temp_file)"
  write_export_options "${export_options_path}"

  exporter_args=(
    -exportArchive
    -archivePath "${archive_path}"
    -exportPath "${export_path}"
    -exportOptionsPlist "${export_options_path}"
  )
  if [[ "${allow_provisioning_updates}" == true ]]; then
    validate_asc_credentials
    exporter_args+=(
      -allowProvisioningUpdates
      -authenticationKeyIssuerID "${asc_issuer_id}"
      -authenticationKeyID "${asc_key_id}"
      -authenticationKeyPath "${asc_key_path}"
    )
  fi

  set +e
  xcodebuild "${exporter_args[@]}" >"${export_log}" 2>&1
  export_status="$?"
  set -e
  if [[ "${export_status}" -ne 0 ]]; then
    if grep -Eiq 'no profiles|no signing certificate|provisioning|authentication|credential|communication with apple' "${export_log}"; then
      echo "Archive export failed because Apple signing or provisioning credentials are unavailable or invalid" >&2
    else
      echo "Archive export failed; Xcode diagnostics were withheld from output" >&2
    fi
    return 1
  fi

  ipa_path="${export_path}/FilmyCamera.ipa"
  validate_exported_ipa "${ipa_path}"
  echo "Release IPA export prepared"
  echo "  bundle: ${bundle_id}"
  echo "  IPA: ${ipa_path}"
}

upload_to_app_store_connect() {
  local transporter_path
  local transporter_work_dir
  local private_keys_dir
  local upload_log
  local upload_status
  local transporter_args

  validate_asc_credentials
  [[ -f "${ipa_path}" ]] || {
    echo "An exported IPA is required before upload" >&2
    return 1
  }
  transporter_path="$(xcrun --find iTMSTransporter 2>/dev/null || true)"
  [[ -n "${transporter_path}" ]] || {
    echo "iTMSTransporter is unavailable; install or select a full Xcode installation" >&2
    return 127
  }

  transporter_work_dir="$(new_temp_dir)"
  private_keys_dir="${transporter_work_dir}/private_keys"
  mkdir -m 700 "${private_keys_dir}"
  if ! cp "${asc_key_path}" "${private_keys_dir}/AuthKey_${asc_key_id}.p8" >/dev/null 2>&1; then
    echo "Unable to stage the App Store Connect private key for Transporter" >&2
    return 1
  fi
  chmod 600 "${private_keys_dir}/AuthKey_${asc_key_id}.p8"
  upload_log="$(new_temp_file)"
  transporter_args=(
    -m upload
    -apiIssuer "${asc_issuer_id}"
    -apiKey "${asc_key_id}"
    -v critical
    -assetFile "${ipa_path}"
  )
  if [[ -f "${export_path}/AppStoreInfo.plist" ]]; then
    transporter_args+=( -assetDescription "${export_path}/AppStoreInfo.plist" )
  fi

  set +e
  (
    cd "${transporter_work_dir}"
    "${transporter_path}" "${transporter_args[@]}"
  ) >"${upload_log}" 2>&1
  upload_status="$?"
  set -e
  if [[ "${upload_status}" -ne 0 ]]; then
    if grep -Eiq 'authentication|api key|issuer|unauthorized|not authorized|credential' "${upload_log}"; then
      echo "App Store Connect upload failed because the supplied credentials were rejected or unavailable" >&2
    else
      echo "App Store Connect upload failed; Transporter diagnostics were withheld from output" >&2
    fi
    return 1
  fi

  echo "App Store Connect upload completed"
  echo "  IPA: ${ipa_path}"
}

run_check() {
  local failures=0

  if ! run_project_preflight; then
    failures=1
  fi

  if ! run_store_metadata_preflight; then
    failures=1
  fi

  if [[ -d "${archive_path}" ]]; then
    if ! validate_archive; then
      failures=1
    fi
  else
    echo "Release archive not found; export/upload preparation requires a validated archive" >&2
    failures=1
  fi

  if ! require_local_distribution_material; then
    failures=1
  fi

  if ! validate_asc_credentials; then
    failures=1
  fi

  if [[ "${failures}" -ne 0 ]]; then
    echo "Release export/upload readiness failed; no export or upload was attempted" >&2
    return 1
  fi

  echo "Release export/upload readiness check passed"
  echo "  no export or upload was attempted"
}

cd "${root_dir}"

case "${mode}" in
  check)
    run_check
    ;;
  export)
    prepare_export
    ;;
  upload)
    validate_asc_credentials
    prepare_export
    upload_to_app_store_connect
    ;;
esac
