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

macho_uuid_records() {
  local binary_path="$1"
  local artifact_name="$2"
  local dwarfdump_output=""
  local line=""
  local uuid=""
  local architecture=""
  local records=""
  local uuid_line_pattern='^UUID:[[:space:]]+([0-9A-Fa-f-]+)[[:space:]]+[(]([^)]*)[)]'

  [[ -f "${binary_path}" ]] || {
    echo "${artifact_name} Mach-O was not found: ${binary_path}" >&2
    return 1
  }

  dwarfdump_output="$(xcrun dwarfdump --uuid "${binary_path}" 2>&1)" || {
    echo "Unable to read Mach-O UUIDs from ${artifact_name}: ${binary_path}" >&2
    printf '%s\n' "${dwarfdump_output}" >&2
    return 1
  }

  while IFS= read -r line; do
    if [[ "${line}" =~ ${uuid_line_pattern} ]]; then
      uuid="${BASH_REMATCH[1]}"
      architecture="${BASH_REMATCH[2]}"
      [[ "${uuid}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || continue
      [[ -n "${architecture}" ]] || continue
      uuid="$(printf '%s' "${uuid}" | tr '[:upper:]' '[:lower:]')"
      architecture="$(printf '%s' "${architecture}" | tr '[:upper:]' '[:lower:]')"
      records+="${architecture}:${uuid}"$'\n'
    fi
  done <<<"${dwarfdump_output}"

  [[ -n "${records}" ]] || {
    echo "${artifact_name} has no readable architecture UUIDs: ${binary_path}" >&2
    return 1
  }

  printf '%s' "${records}" | LC_ALL=C sort -u
}

print_uuid_records() {
  local records="$1"
  while IFS= read -r record; do
    [[ -n "${record}" ]] && printf '    %s\n' "${record}" >&2
  done <<<"${records}"
}

bundle_id="$(plist_value CFBundleIdentifier)"
version="$(plist_value CFBundleShortVersionString)"
build="$(plist_value CFBundleVersion)"
executable_name="$(plist_value CFBundleExecutable || true)"

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

[[ -n "${executable_name}" && "${executable_name}" != */* && "${executable_name}" != "." && "${executable_name}" != ".." ]] || {
  echo "Archive has an invalid or missing CFBundleExecutable: ${executable_name:-missing}" >&2
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
profile_expiration_epoch="$(
  date -j -f '%Y-%m-%d %H:%M:%S %z' "${profile_expiration}" '+%s' 2>/dev/null \
    || date -j -f '%Y-%m-%dT%H:%M:%SZ' "${profile_expiration}" '+%s' 2>/dev/null \
    || date -j -f '%a %b %d %H:%M:%S %Z %Y' "${profile_expiration}" '+%s' 2>/dev/null \
    || true
)"

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

command -v xcrun >/dev/null || {
  echo "Xcode command-line tools are required to inspect Mach-O UUIDs" >&2
  exit 127
}

app_executable_path="${app_path}/${executable_name}"
dsym_executable_path="${dsym_path}/Contents/Resources/DWARF/${executable_name}"
app_uuid_records="$(macho_uuid_records "${app_executable_path}" "Archive app executable")" || exit 1
dsym_uuid_records="$(macho_uuid_records "${dsym_executable_path}" "Archive app dSYM")" || exit 1
[[ "${app_uuid_records}" == "${dsym_uuid_records}" ]] || {
  echo "Archive app executable and dSYM architecture UUIDs do not match" >&2
  echo "  executable UUIDs:" >&2
  print_uuid_records "${app_uuid_records}"
  echo "  dSYM UUIDs:" >&2
  print_uuid_records "${dsym_uuid_records}"
  echo "Rebuild the archive so its executable and dSYM come from the same Release build." >&2
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

echo "Release archive validated"
echo "  bundle: ${bundle_id}"
echo "  version: ${version} (${build})"
echo "  signing: ${authority}"
echo "  archive: ${archive_path}"
