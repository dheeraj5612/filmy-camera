#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/../.." && pwd)"
project_spec="${root_dir}/project.yml"
project_file="${root_dir}/FilmyCamera.xcodeproj"
info_plist="${root_dir}/FilmyCamera/Info.plist"
privacy_manifest="${root_dir}/FilmyCamera/Resources/PrivacyInfo.xcprivacy"
icon_file="${root_dir}/FilmyCamera/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

failures=0

require_file() {
  local path="$1"
  local description="$2"
  if [[ ! -e "${path}" ]]; then
    echo "Missing ${description}: ${path}" >&2
    failures=$((failures + 1))
  fi
}

require_spec_value() {
  local value="$1"
  local description="$2"
  if ! grep -Fq "${value}" "${project_spec}"; then
    echo "Missing ${description} in project.yml: ${value}" >&2
    failures=$((failures + 1))
  fi
}

require_file "${project_spec}" "XcodeGen specification"
require_file "${project_file}" "generated Xcode project"
require_file "${info_plist}" "Info.plist"
require_file "${privacy_manifest}" "privacy manifest"
require_file "${icon_file}" "1024px app icon"

if [[ "${failures}" -gt 0 ]]; then
  exit 1
fi

if ! plutil -lint "${info_plist}" >/dev/null; then
  echo "Info.plist is not valid" >&2
  failures=$((failures + 1))
fi

if ! plutil -lint "${privacy_manifest}" >/dev/null; then
  echo "PrivacyInfo.xcprivacy is not valid" >&2
  failures=$((failures + 1))
fi

require_spec_value 'PRODUCT_BUNDLE_IDENTIFIER: com.dheeraj.filmycamera' "production bundle identifier"
require_spec_value 'MARKETING_VERSION: "1.0.0"' "marketing version"
require_spec_value 'DEVELOPMENT_TEAM: 6ALSCF5GBV' "development team"
require_spec_value 'CFBundleDisplayName: Filmy Camera' "display name"
require_spec_value 'ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon' "app icon configuration"
require_spec_value 'NSCameraUsageDescription:' "camera permission copy"
require_spec_value 'NSPhotoLibraryAddUsageDescription:' "photo-add permission copy"
require_spec_value 'NSPhotoLibraryUsageDescription:' "photo-read permission copy"
require_spec_value 'ITSAppUsesNonExemptEncryption: false' "export-compliance declaration"

build_number="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' "${project_spec}" | head -n 1)"
if [[ -z "${build_number}" ]] || [[ ! "${build_number}" =~ ^[1-9][0-9]*$ ]]; then
  echo "CURRENT_PROJECT_VERSION must be a positive integer in project.yml" >&2
  failures=$((failures + 1))
fi

marketing_version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' "${project_spec}" | head -n 1)"

if ! grep -Fq 'NSPrivacyTracking' "${privacy_manifest}" \
  || ! grep -Fq 'NSPrivacyCollectedDataTypes' "${privacy_manifest}" \
  || ! grep -Fq 'NSPrivacyAccessedAPICategoryUserDefaults' "${privacy_manifest}"; then
  echo "Privacy manifest is missing required declarations" >&2
  failures=$((failures + 1))
fi

if ! /usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "${info_plist}" 2>/dev/null | grep -Fxq 'false'; then
  echo "Info.plist must declare exempt export compliance" >&2
  failures=$((failures + 1))
fi

icon_has_alpha="$(sips -g hasAlpha "${icon_file}" 2>/dev/null | awk -F': ' '/hasAlpha/ { print $2; exit }')"
if [[ "${icon_has_alpha}" == "yes" ]]; then
  echo "App icon must be opaque; iOS applies the platform mask: ${icon_file}" >&2
  failures=$((failures + 1))
fi

icon_dimensions="$(sips -g pixelWidth -g pixelHeight "${icon_file}" 2>/dev/null || true)"
if ! grep -Fq 'pixelWidth: 1024' <<<"${icon_dimensions}" \
  || ! grep -Fq 'pixelHeight: 1024' <<<"${icon_dimensions}"; then
  echo "App icon must be 1024x1024: ${icon_file}" >&2
  failures=$((failures + 1))
fi

if ! command -v xcodebuild >/dev/null; then
  echo "xcodebuild is required for project preflight" >&2
  exit 127
fi

project_summary="$(xcodebuild -project "${project_file}" -list 2>&1)" || {
  printf '%s\n' "${project_summary}" >&2
  echo "Unable to inspect generated Xcode project" >&2
  exit 1
}

if ! grep -Fq 'FilmyCamera' <<<"${project_summary}" \
  || ! grep -Fq 'FilmyCameraTests' <<<"${project_summary}" \
  || ! grep -Fq 'FilmyCameraUITests' <<<"${project_summary}"; then
  echo "Generated project is missing the production scheme or test targets" >&2
  failures=$((failures + 1))
fi

if [[ "${failures}" -gt 0 ]]; then
  exit 1
fi

echo "Release project preflight passed"
echo "  bundle: com.dheeraj.filmycamera"
echo "  version: ${marketing_version} (${build_number})"
echo "  privacy manifest: present"
echo "  app icon: 1024x1024"
echo "  scheme/tests: present"
