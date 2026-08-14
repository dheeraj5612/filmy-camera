#!/usr/bin/env bash
set -euo pipefail

# Validates an already-exported App Store distribution IPA without running
# App Store Connect metadata or upload gates. This is useful when a local
# archive is ready but the account owner has not yet finalized store pricing,
# availability, or upload credentials.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/../.." && pwd)"
ipa_path=""
archive_path="${FILMY_ARCHIVE_PATH:-}"
temp_paths=()

usage() {
  cat <<'EOF'
Usage:
  scripts/release/validate-ipa.sh --ipa PATH --archive PATH

Options:
  --ipa PATH       Exported FilmyCamera.ipa to validate.
  --archive PATH   Validated source archive used to create the IPA.
  -h, --help       Show this help.

This command validates bundle/version/build parity, App Store provisioning,
distribution signing, privacy manifest presence, and archive source
provenance. It does not contact Apple or upload anything.
EOF
}

die() {
  echo "IPA validation error: $*" >&2
  exit 64
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --ipa)
      [[ "$#" -ge 2 ]] || die "--ipa requires a path"
      ipa_path="$2"
      shift 2
      ;;
    --archive)
      [[ "$#" -ge 2 ]] || die "--archive requires a path"
      archive_path="$2"
      shift 2
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

[[ -n "${ipa_path}" ]] || die "--ipa is required"
[[ -n "${archive_path}" ]] || die "--archive is required"

[[ "${ipa_path}" = /* ]] || ipa_path="${root_dir}/${ipa_path}"
[[ "${archive_path}" = /* ]] || archive_path="${root_dir}/${archive_path}"
[[ -f "${ipa_path}" ]] || die "IPA was not found: ${ipa_path}"
[[ -d "${archive_path}" ]] || die "archive was not found: ${archive_path}"

cleanup() {
  local path
  ((${#temp_paths[@]})) || return 0
  for path in "${temp_paths[@]}"; do
    [[ -n "${path}" ]] && rm -rf "${path}"
  done
}
trap cleanup EXIT HUP INT TERM

plist_value() {
  local key="$1"
  local plist_path="$2"
  /usr/libexec/PlistBuddy -c "Print :${key}" "${plist_path}" 2>/dev/null
}

profile_value() {
  local key="$1"
  local plist_path="$2"
  /usr/libexec/PlistBuddy -c "Print :Entitlements:${key}" "${plist_path}" 2>/dev/null || true
}

profile_expiration_epoch() {
  local expiration_date="$1"
  date -j -f '%Y-%m-%d %H:%M:%S %z' "${expiration_date}" '+%s' 2>/dev/null \
    || date -j -f '%Y-%m-%dT%H:%M:%SZ' "${expiration_date}" '+%s' 2>/dev/null \
    || date -j -f '%a %b %d %H:%M:%S %Z %Y' "${expiration_date}" '+%s' 2>/dev/null \
    || true
}

"${script_dir}/validate-archive.sh" "${archive_path}" >/dev/null

archive_app_path="${archive_path}/Products/Applications/FilmyCamera.app"
archive_info_plist="${archive_app_path}/Info.plist"
archive_bundle_id="$(plist_value CFBundleIdentifier "${archive_info_plist}")"
archive_version="$(plist_value CFBundleShortVersionString "${archive_info_plist}")"
archive_build="$(plist_value CFBundleVersion "${archive_info_plist}")"

work_dir="$(mktemp -d -t filmycamera-ipa-validation)"
temp_paths+=("${work_dir}")
unzip -qq "${ipa_path}" -d "${work_dir}" || die "IPA is not a valid ZIP archive"

app_path="${work_dir}/Payload/FilmyCamera.app"
info_plist="${app_path}/Info.plist"
[[ -d "${app_path}" && -f "${info_plist}" ]] || die "IPA does not contain FilmyCamera.app"

bundle_id="$(plist_value CFBundleIdentifier "${info_plist}")"
version="$(plist_value CFBundleShortVersionString "${info_plist}")"
build="$(plist_value CFBundleVersion "${info_plist}")"
[[ "${bundle_id}" == "${archive_bundle_id}" \
  && "${version}" == "${archive_version}" \
  && "${build}" == "${archive_build}" ]] || {
  die "IPA metadata does not match the validated archive"
}

[[ -f "${app_path}/PrivacyInfo.xcprivacy" ]] || {
  die "IPA is missing PrivacyInfo.xcprivacy"
}
[[ -f "${app_path}/embedded.mobileprovision" ]] || {
  die "IPA has no embedded provisioning profile"
}

profile_plist="$(mktemp -t filmycamera-ipa-profile)"
temp_paths+=("${profile_plist}")
security cms -D -i "${app_path}/embedded.mobileprovision" -o "${profile_plist}" 2>/dev/null || {
  die "unable to decode the embedded provisioning profile"
}

application_identifier="$(profile_value application-identifier "${profile_plist}")"
profile_team_id="${application_identifier%%.*}"
profile_bundle_id="${application_identifier#*.}"
profile_get_task_allow="$(profile_value get-task-allow "${profile_plist}")"
profile_expiration="$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "${profile_plist}" 2>/dev/null || true)"
profile_expiration_epoch="$(profile_expiration_epoch "${profile_expiration}")"
expected_team="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM:[[:space:]]*\([^[:space:]]*\)[[:space:]]*$/\1/p' "${root_dir}/project.yml" | head -n 1)"

[[ "${profile_bundle_id}" == "${bundle_id}" && "${profile_team_id}" == "${expected_team}" ]] || {
  die "embedded profile does not match the production bundle/team"
}
[[ "${profile_get_task_allow}" == false ]] || {
  die "distribution IPA must disable get-task-allow"
}
if /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "${profile_plist}" >/dev/null 2>&1; then
  die "App Store IPA must not contain ProvisionedDevices"
fi
[[ -n "${profile_expiration_epoch}" && "${profile_expiration_epoch}" -gt "$(date '+%s')" ]] || {
  die "embedded provisioning profile is expired or unreadable"
}

codesign --verify --deep --strict --verbose=2 "${app_path}" >/dev/null 2>&1 || {
  die "IPA app signature failed verification"
}
signature_details="$(codesign -dv --verbose=4 "${app_path}" 2>&1 || true)"
authority="$(sed -n 's/^Authority=//p' <<<"${signature_details}" | head -n 1)"
case "${authority}" in
  "Apple Distribution:"*|"iPhone Distribution:"*) ;;
  *) die "IPA is not signed for App Store distribution" ;;
esac

echo "Distribution IPA validated"
echo "  bundle: ${bundle_id}"
echo "  version: ${version} (${build})"
echo "  signing: ${authority}"
echo "  archive: ${archive_path}"
echo "  IPA: ${ipa_path}"
