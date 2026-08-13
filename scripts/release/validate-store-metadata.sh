#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/../.." && pwd)"
final_mode=false

if [[ "${1:-}" == "--final" ]]; then
  final_mode=true
  shift
fi

metadata_file="${1:-${root_dir}/docs/app-store/metadata-en-US.md}"

if [[ ! -f "${metadata_file}" ]]; then
  echo "Missing App Store metadata file: ${metadata_file}" >&2
  exit 1
fi

field_value() {
  local label="$1"
  local value
  value="$(sed -n "s/^- \*\*${label}:\*\*[[:space:]]*//p" "${metadata_file}" | head -n 1)"
  printf '%s\n' "${value}" | sed -E 's/^`([^`]*)`.*/\1/; s/^`//; s/`$//'
}

character_count() {
  printf '%s' "$1" | LC_ALL=en_US.UTF-8 wc -m | tr -d '[:space:]'
}

failures=0

require_value() {
  local label="$1"
  local value
  value="$(field_value "${label}")"
  if [[ -z "${value}" ]]; then
    echo "Missing metadata field: ${label}" >&2
    failures=$((failures + 1))
  fi
}

check_max_length() {
  local label="$1"
  local maximum="$2"
  local value
  local length
  value="$(field_value "${label}")"
  length="$(character_count "${value}")"
  if [[ "${length}" -gt "${maximum}" ]]; then
    echo "${label} exceeds ${maximum} characters (${length})" >&2
    failures=$((failures + 1))
  fi
  echo "  ${label}: ${length}/${maximum} characters"
}

require_value "App name"
require_value "Subtitle"
require_value "Promotional text"
require_value "Support URL"
require_value "Marketing URL"
require_value "Privacy policy URL"

check_max_length "App name" 30
check_max_length "Subtitle" 30
check_max_length "Promotional text" 170

keywords_line="$(awk '/^`.*`$/ { print substr($0, 2, length($0) - 2); exit }' "${metadata_file}")"
if [[ -z "${keywords_line}" ]]; then
  echo "Missing comma-separated keyword field" >&2
  failures=$((failures + 1))
else
  keyword_length="$(character_count "${keywords_line}")"
  if [[ "${keyword_length}" -gt 100 ]]; then
    echo "Keywords exceed 100 characters (${keyword_length})" >&2
    failures=$((failures + 1))
  fi
  echo "  Keywords: ${keyword_length}/100 characters"
fi

for label in "Support URL" "Marketing URL" "Privacy policy URL"; do
  value="$(field_value "${label}")"
  if [[ "${value}" != https://* ]]; then
    echo "${label} must use an HTTPS URL" >&2
    failures=$((failures + 1))
  fi
done

if ! grep -Fq "It is not affiliated with Fujifilm" "${metadata_file}"; then
  echo "Metadata must retain the independent-product trademark disclaimer" >&2
  failures=$((failures + 1))
fi

if ! grep -Fq "## App Review notes" "${metadata_file}" \
  || ! grep -Fq "the Roll only reads frames saved by Filmy Camera" "${metadata_file}"; then
  echo "Metadata must include truthful App Review notes for the current Roll behavior" >&2
  failures=$((failures + 1))
fi

if [[ "${final_mode}" == true ]]; then
  status_line="$(sed -n 's/^Status:[[:space:]]*//p' "${metadata_file}" | head -n 1)"
  if [[ "${status_line}" != "final" ]]; then
    echo "Final App Store metadata must begin with Status: final" >&2
    failures=$((failures + 1))
  fi

  for label in "Price" "Availability"; do
    value="$(field_value "${label}")"
    if [[ -z "${value}" || "${value}" == *"Confirm "* || "${value}" == *"["* || "${value}" == *"]"* ]]; then
      echo "Final App Store metadata must resolve ${label}" >&2
      failures=$((failures + 1))
    fi
  done

  if grep -Eq 'Status:[[:space:]]*draft|Confirm with the product owner|\[release owner|\[TODO|TBD' "${metadata_file}"; then
    echo "Final App Store metadata still contains draft placeholders" >&2
    failures=$((failures + 1))
  fi
fi

if [[ "${failures}" -gt 0 ]]; then
  echo "App Store metadata validation failed" >&2
  exit 1
fi

echo "App Store metadata validation passed"
