#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/../.." && pwd)"
icon_file="${root_dir}/FilmyCamera/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
screenshot_dir="${root_dir}/docs/app-store/screenshots/iphone-6.5"

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

if [[ "${failures}" -gt 0 ]]; then
  echo "App Store media validation failed" >&2
  exit 1
fi

echo "App Store media validation passed"
echo "  app icon: 1024x1024 opaque PNG"
echo "  screenshots: ${#expected_screenshots[@]} x 1242x2688 JPEG"
echo "  slot: iPhone 6.5-inch Display"
