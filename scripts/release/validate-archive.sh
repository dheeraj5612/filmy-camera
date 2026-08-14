#!/usr/bin/env bash
set -euo pipefail

archive_path="${1:-${FILMY_ARCHIVE_PATH:-}}"
if [[ -z "${archive_path}" ]]; then
  echo "Usage: $0 /path/to/FilmyCamera.xcarchive" >&2
  exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/../.." && pwd)"
project_spec="${root_dir}/project.yml"
expected_team="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM:[[:space:]]*\([^[:space:]]*\)[[:space:]]*$/\1/p' "${project_spec}" | head -n 1)"
source_sha_path=""
source_revision=""

if [[ ! -d "${archive_path}" ]]; then
  echo "Archive not found: ${archive_path}" >&2
  exit 1
fi

source_revision="$(git -C "${root_dir}" rev-parse --verify HEAD 2>/dev/null)" || {
  echo "Unable to determine the current source revision" >&2
  exit 1
}

[[ -z "$(git -C "${root_dir}" status --porcelain --untracked-files=all)" ]] || {
  echo "Archive validation requires a clean source checkout" >&2
  exit 1
}

source_sha_path="${archive_path}/FilmyCamera.source-sha"
[[ -f "${source_sha_path}" ]] || {
  echo "Archive has no source revision provenance" >&2
  exit 1
}

archive_source_revision="$(<"${source_sha_path}")"
[[ "${archive_source_revision}" == "${source_revision}" ]] || {
  echo "Archive source revision does not match the current checkout" >&2
  exit 1
}

app_path="${archive_path}/Products/Applications/FilmyCamera.app"
info_plist="${app_path}/Info.plist"
dsym_path="${archive_path}/dSYMs/FilmyCamera.app.dSYM"
profile_plist=""

cleanup() {
  if [[ -n "${profile_plist}" ]]; then
    rm -f "${profile_plist}"
  fi
}
trap cleanup EXIT

if [[ ! -d "${app_path}" || ! -f "${info_plist}" ]]; then
  echo "Archive does not contain FilmyCamera.app: ${archive_path}" >&2
  exit 1
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "${info_plist}" 2>/dev/null
}

bundle_id="$(plist_value CFBundleIdentifier)"
version="$(plist_value CFBundleShortVersionString)"
build="$(plist_value CFBundleVersion)"

expected_version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' "${project_spec}" | head -n 1)"
expected_build="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' "${project_spec}" | head -n 1)"

[[ "${bundle_id}" == "com.dheeraj.filmycamera" ]] || {
  echo "Unexpected bundle identifier: ${bundle_id}" >&2
  exit 1
}

[[ -n "${version}" && -n "${build}" ]] || {
  echo "Archive is missing marketing version or build number" >&2
  exit 1
}

[[ "${version}" == "${expected_version}" && "${build}" == "${expected_build}" ]] || {
  echo "Archive version/build ${version} (${build}) does not match project.yml ${expected_version} (${expected_build})" >&2
  exit 1
}

[[ -f "${app_path}/embedded.mobileprovision" ]] || {
  echo "Archive has no embedded provisioning profile" >&2
  exit 1
}

command -v security >/dev/null || {
  echo "The macOS security tool is required to inspect the provisioning profile" >&2
  exit 127
}

profile_plist="$(mktemp -t filmycamera-profile)"
security cms -D -i "${app_path}/embedded.mobileprovision" -o "${profile_plist}" 2>/dev/null || {
  echo "Unable to decode the embedded provisioning profile" >&2
  exit 1
}

profile_value() {
  /usr/libexec/PlistBuddy -c "Print :Entitlements:$1" "${profile_plist}" 2>/dev/null || true
}

application_identifier="$(profile_value application-identifier)"
profile_team_id="${application_identifier%%.*}"
profile_bundle_id="${application_identifier#*.}"
profile_get_task_allow="$(profile_value get-task-allow)"
profile_expiration="$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "${profile_plist}" 2>/dev/null || true)"
profile_expiration_epoch="$(date -j -f '%Y-%m-%d %H:%M:%S %z' "${profile_expiration}" '+%s' 2>/dev/null || true)"

[[ "${profile_bundle_id}" == "${bundle_id}" ]] || {
  echo "Provisioning profile bundle identifier does not match app: ${profile_bundle_id}" >&2
  exit 1
}

[[ -n "${profile_team_id}" ]] || {
  echo "Provisioning profile has no team identifier" >&2
  exit 1
}

[[ -n "${expected_team}" && "${profile_team_id}" == "${expected_team}" ]] || {
  echo "Provisioning profile belongs to an unexpected team: ${profile_team_id} (expected ${expected_team:-unknown})" >&2
  exit 1
}

[[ "${profile_get_task_allow}" == "false" ]] || {
  echo "Distribution archive must disable get-task-allow" >&2
  exit 1
}

if /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "${profile_plist}" >/dev/null 2>&1; then
  echo "App Store distribution archive must not contain ProvisionedDevices" >&2
  exit 1
fi

[[ -n "${profile_expiration_epoch}" && "${profile_expiration_epoch}" -gt "$(date '+%s')" ]] || {
  echo "Embedded provisioning profile is expired or has an unreadable expiration date" >&2
  exit 1
}

[[ -d "${dsym_path}" ]] || {
  echo "Archive has no app dSYM" >&2
  exit 1
}

[[ -f "${app_path}/PrivacyInfo.xcprivacy" ]] || {
  echo "Archive is missing PrivacyInfo.xcprivacy" >&2
  exit 1
}

codesign_details="$(codesign -dv --verbose=4 "${app_path}" 2>&1)" || {
  echo "Unable to inspect app signature" >&2
  printf '%s\n' "${codesign_details}" >&2
  exit 1
}

if grep -q "code object is not signed at all" <<<"${codesign_details}"; then
  echo "Archive is unsigned" >&2
  exit 1
fi

authority="$(sed -n 's/^Authority=//p' <<<"${codesign_details}" | head -n 1)"
case "${authority}" in
  "Apple Distribution:"*|"iPhone Distribution:"*) ;;
  *)
    echo "Archive is not signed for App Store distribution: ${authority:-unknown}" >&2
    exit 1
    ;;
esac

codesign --verify --deep --strict --verbose=2 "${app_path}" >/dev/null
xcrun dwarfdump --uuid "${dsym_path}" >/dev/null

echo "Release archive validated"
echo "  bundle: ${bundle_id}"
echo "  version: ${version} (${build})"
echo "  signing: ${authority}"
echo "  archive: ${archive_path}"
