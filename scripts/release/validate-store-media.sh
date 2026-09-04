#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/../.." && pwd)"
icon_file="${root_dir}/FilmyCamera/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
screenshot_dir="${root_dir}/docs/app-store/screenshots/iphone-6.5"
current_screenshot_names=(
  "01-g7x-import.png"
  "02-film-import.png"
  "03-monochrome-import.png"
  "04-roll.png"
  "05-photo-detail.png"
)
current_screenshot_sets=(
  "${root_dir}/docs/app-store/screenshots/iphone-6.5-current|iPhone 6.5-inch|1242|2688"
  "${root_dir}/docs/app-store/screenshots/ipad-13-current|iPad 13-inch|2064|2752"
)

expected_screenshots=(
  "01-camera-preview.jpg"
  "02-settings.jpg"
  "03-camera-rail.jpg"
  "04-recipe-details.jpg"
  "05-roll.jpg"
)

failures=0

require_file() {
  local path="$1"
  local description="$2"
  if [[ ! -f "${path}" ]]; then
    echo "Missing ${description}: ${path}" >&2
    failures=$((failures + 1))
  fi
}

require_file "${icon_file}" "1024px app icon"
require_file "${screenshot_dir}/README.md" "App Store screenshot manifest"

if ! command -v sips >/dev/null 2>&1; then
  echo "sips is required for App Store media validation" >&2
  exit 127
fi

if [[ -f "${icon_file}" ]]; then
  icon_dimensions="$(sips -g pixelWidth -g pixelHeight "${icon_file}" 2>/dev/null || true)"
  if ! grep -Fq 'pixelWidth: 1024' <<<"${icon_dimensions}" \
    || ! grep -Fq 'pixelHeight: 1024' <<<"${icon_dimensions}"; then
    echo "App icon must be 1024x1024: ${icon_file}" >&2
    failures=$((failures + 1))
  fi

  icon_has_alpha="$(sips -g hasAlpha "${icon_file}" 2>/dev/null | awk -F': ' '/hasAlpha/ { print $2; exit }')"
  if [[ "${icon_has_alpha}" == "yes" ]]; then
    echo "App icon must be opaque: ${icon_file}" >&2
    failures=$((failures + 1))
  fi
fi

if [[ -d "${screenshot_dir}" ]]; then
  screenshot_count=0
  screenshot_hashes=""
  for filename in "${expected_screenshots[@]}"; do
    screenshot_file="${screenshot_dir}/${filename}"
    require_file "${screenshot_file}" "6.5-inch screenshot"
    if [[ ! -f "${screenshot_file}" ]]; then
      continue
    fi

    screenshot_count=$((screenshot_count + 1))
    file_description="$(file -b "${screenshot_file}")"
    if [[ "${file_description}" != JPEG\ image\ data* ]]; then
      echo "Screenshot must be a JPEG: ${screenshot_file}" >&2
      failures=$((failures + 1))
    fi

    screenshot_dimensions="$(sips -g pixelWidth -g pixelHeight "${screenshot_file}" 2>/dev/null || true)"
    if ! grep -Fq 'pixelWidth: 1242' <<<"${screenshot_dimensions}" \
      || ! grep -Fq 'pixelHeight: 2688' <<<"${screenshot_dimensions}"; then
      echo "Screenshot must be 1242x2688: ${screenshot_file}" >&2
      failures=$((failures + 1))
    fi

    screenshot_hash="$(shasum -a 256 "${screenshot_file}" | awk '{ print $1 }')"
    if grep -Fq "${screenshot_hash}" <<<"${screenshot_hashes}"; then
      echo "Duplicate screenshot content: ${screenshot_file}" >&2
      failures=$((failures + 1))
    fi
    screenshot_hashes+="${screenshot_hash}"$'\n'
  done

  if [[ "${screenshot_count}" -ne "${#expected_screenshots[@]}" ]]; then
    echo "Expected ${#expected_screenshots[@]} App Store screenshots; found ${screenshot_count}" >&2
    failures=$((failures + 1))
  fi
fi

validate_current_screenshot_set() {
  local current_dir="$1"
  local device_name="$2"
  local expected_width="$3"
  local expected_height="$4"
  local screenshot_count=0
  local screenshot_hashes=""
  local screenshot_file file_description screenshot_dimensions screenshot_hash actual_png_count

  require_file "${current_dir}/README.md" "${device_name} screenshot manifest"
  if [[ ! -d "${current_dir}" ]]; then
    return
  fi

  for filename in "${current_screenshot_names[@]}"; do
    screenshot_file="${current_dir}/${filename}"
    require_file "${screenshot_file}" "${device_name} screenshot"
    if [[ ! -f "${screenshot_file}" ]]; then
      continue
    fi

    screenshot_count=$((screenshot_count + 1))
    file_description="$(file -b "${screenshot_file}")"
    if [[ "${file_description}" != PNG\ image\ data* ]]; then
      echo "Screenshot must be a PNG: ${screenshot_file}" >&2
      failures=$((failures + 1))
    fi

    screenshot_dimensions="$(sips -g pixelWidth -g pixelHeight "${screenshot_file}" 2>/dev/null || true)"
    if ! grep -Fq "pixelWidth: ${expected_width}" <<<"${screenshot_dimensions}" \
      || ! grep -Fq "pixelHeight: ${expected_height}" <<<"${screenshot_dimensions}"; then
      echo "Screenshot must be ${expected_width}x${expected_height}: ${screenshot_file}" >&2
      failures=$((failures + 1))
    fi

    screenshot_hash="$(shasum -a 256 "${screenshot_file}" | awk '{ print $1 }')"
    if grep -Fq "${screenshot_hash}" <<<"${screenshot_hashes}"; then
      echo "Duplicate screenshot content: ${screenshot_file}" >&2
      failures=$((failures + 1))
    fi
    screenshot_hashes+="${screenshot_hash}"$'\n'
  done

  actual_png_count="$(find "${current_dir}" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')"
  if [[ "${screenshot_count}" -ne "${#current_screenshot_names[@]}" \
    || "${actual_png_count}" -ne "${#current_screenshot_names[@]}" ]]; then
    echo "Expected ${#current_screenshot_names[@]} ${device_name} PNG screenshots; found ${actual_png_count}" >&2
    failures=$((failures + 1))
  fi
}

for screenshot_set in "${current_screenshot_sets[@]}"; do
  IFS='|' read -r current_dir device_name expected_width expected_height <<<"${screenshot_set}"
  validate_current_screenshot_set "${current_dir}" "${device_name}" "${expected_width}" "${expected_height}"
done

if [[ "${failures}" -gt 0 ]]; then
  echo "App Store media validation failed" >&2
  exit 1
fi

echo "App Store media validation passed"
echo "  app icon: 1024x1024 opaque PNG"
echo "  screenshots: ${#expected_screenshots[@]} x 1242x2688 JPEG"
echo "  slot: iPhone 6.5-inch Display"
echo "  current iPhone screenshots: ${#current_screenshot_names[@]} x 1242x2688 PNG"
echo "  current iPad screenshots: ${#current_screenshot_names[@]} x 2064x2752 PNG"
