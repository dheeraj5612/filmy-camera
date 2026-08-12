#!/usr/bin/env bash
set -euo pipefail

archive_path="${1:-${FILMY_ARCHIVE_PATH:-}}"
if [[ -z "${archive_path}" ]]; then
  echo "Usage: $0 /path/to/FilmyCamera.xcarchive" >&2
  exit 64
fi

if [[ ! -d "${archive_path}" ]]; then
  echo "Archive not found: ${archive_path}" >&2
  exit 1
fi

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

[[ "${bundle_id}" == "com.dheeraj.filmycamera" ]] || {
  echo "Unexpected bundle identifier: ${bundle_id}" >&2
  exit 1
}

[[ -n "${version}" && -n "${build}" ]] || {
  echo "Archive is missing marketing version or build number" >&2
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

[[ "${profile_bundle_id}" == "${bundle_id}" ]] || {
  echo "Provisioning profile bundle identifier does not match app: ${profile_bundle_id}" >&2
  exit 1
}

[[ -n "${profile_team_id}" ]] || {
  echo "Provisioning profile has no team identifier" >&2
  exit 1
}

[[ "${profile_team_id}" == "AQW5C8DEEG" ]] || {
  echo "Provisioning profile belongs to an unexpected team: ${profile_team_id}" >&2
  exit 1
}

[[ "${profile_get_task_allow}" == "false" ]] || {
  echo "Distribution archive must disable get-task-allow" >&2
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
