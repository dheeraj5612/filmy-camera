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
