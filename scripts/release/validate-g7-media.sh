#!/usr/bin/env bash
set -euo pipefail

# G7 media is intentionally separate from the Filmy Camera store pack. Keep
# this gate strict so a missing or cross-target asset cannot pass by fallback.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/../.." && pwd)"
# shellcheck source=app-config.sh
source "${root_dir}/scripts/release/app-config.sh"

[[ "${release_app_variant}" == "g7" ]] || {
  echo "G7 media validator requires FILMY_APP_VARIANT=g7" >&2
  exit 64
}

failures=0
icon_file="${release_app_icon_path}"
iphone_dir="${release_app_store_iphone_dir}"
ipad_dir="${release_app_store_ipad_dir}"
expected_names=(
  "01-camera.png"
  "02-quick-settings.png"
  "03-date-stamp.png"
  "04-roll.png"
  "05-photo-detail.png"
)

require_file() {
  local path="$1"
  local description="$2"
  if [[ ! -f "${path}" ]]; then
    echo "Missing ${description}: ${path}" >&2
    failures=$((failures + 1))
  fi
}

require_dimensions() {
  local path="$1"
  local label="$2"
  local expected_width="$3"
  local expected_height="$4"
  local dimensions
  dimensions="$(sips -g pixelWidth -g pixelHeight "${path}" 2>/dev/null || true)"
  if ! grep -Fq "pixelWidth: ${expected_width}" <<<"${dimensions}" \
    || ! grep -Fq "pixelHeight: ${expected_height}" <<<"${dimensions}"; then
    echo "${label} must be ${expected_width}x${expected_height}: ${path}" >&2
    failures=$((failures + 1))
  fi
}

require_file "${icon_file}" "G7 1024px app icon"
if [[ -f "${icon_file}" ]]; then
  require_dimensions "${icon_file}" "G7 app icon" 1024 1024
  icon_has_alpha="$(sips -g hasAlpha "${icon_file}" 2>/dev/null | awk -F': ' '/hasAlpha/ { print $2; exit }')"
  if [[ "${icon_has_alpha}" == "yes" ]]; then
    echo "G7 app icon must be opaque: ${icon_file}" >&2
    failures=$((failures + 1))
  fi
fi

validate_set() {
  local directory="$1"
  local label="$2"
  local expected_width="$3"
  local expected_height="$4"
  local filename
  local screenshot_path
  local extra_screenshot

  if [[ ! -d "${directory}" ]]; then
    echo "Missing G7 ${label} screenshot directory: ${directory}" >&2
    failures=$((failures + 1))
    return
  fi
  for filename in "${expected_names[@]}"; do
    screenshot_path="${directory}/${filename}"
    require_file "${screenshot_path}" "G7 ${label} screenshot"
    if [[ -f "${screenshot_path}" ]]; then
      if [[ "$(file -b "${screenshot_path}")" != PNG\ image\ data* ]]; then
        echo "G7 ${label} screenshot must be a PNG: ${screenshot_path}" >&2
        failures=$((failures + 1))
      fi
      require_dimensions "${screenshot_path}" "G7 ${label} screenshot" "${expected_width}" "${expected_height}"
    fi
  done
  extra_screenshot="$(find "${directory}" -maxdepth 1 -type f -name '*.png' -print | while IFS= read -r screenshot_path; do basename "${screenshot_path}"; done | LC_ALL=C sort | comm -23 - <(printf '%s\n' "${expected_names[@]}" | LC_ALL=C sort) | head -n 1)"
  if [[ -n "${extra_screenshot}" ]]; then
    echo "Unexpected G7 ${label} screenshot: ${directory}/${extra_screenshot}" >&2
    failures=$((failures + 1))
  fi
}

command -v sips >/dev/null 2>&1 || {
  echo "sips is required for G7 App Store media validation" >&2
  exit 127
}
validate_set "${iphone_dir}" "iPhone" "${release_app_iphone_width}" "${release_app_iphone_height}"
validate_set "${ipad_dir}" "iPad" "${release_app_ipad_width}" "${release_app_ipad_height}"

if [[ "${failures}" -gt 0 ]]; then
  echo "G7 App Store media validation failed" >&2
  exit 1
fi
echo "G7 App Store media validation passed"
