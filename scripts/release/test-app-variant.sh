#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/../.." && pwd)"

assert_variant() {
  local variant="$1"
  local expected_target="$2"
  local expected_bundle="$3"
  local expected_display_name="$4"
  local expected_project_file="$5"
  local expected_project_spec="$6"
  local expected_project_relative="$7"
  FILMY_APP_VARIANT="${variant}" bash -c '
    set -euo pipefail
    root_dir="$1"
    source "$2/app-config.sh"
    [[ "$release_app_target" == "$3" ]]
    [[ "$release_app_bundle_id" == "$4" ]]
    [[ "$release_app_display_name" == "$5" ]]
    [[ "$release_app_project_file" == "$6" ]]
    [[ "$release_app_project_spec" == "$7" ]]
    [[ "$release_app_project_relative" == "$8" ]]
  ' -- "${root_dir}" "${script_dir}" "${expected_target}" "${expected_bundle}" "${expected_display_name}" "${expected_project_file}" "${expected_project_spec}" "${expected_project_relative}"
}

assert_variant filmy FilmyCamera com.dheeraj.filmycamera "Filmy Camera" \
  "${root_dir}/FilmyCamera.xcodeproj" "${root_dir}/project.yml" "FilmyCamera.xcodeproj"
assert_variant g7 G7Camera com.dheeraj.g7camera "G7X Camera" \
  "${root_dir}/G7Camera/G7Camera.xcodeproj" "${root_dir}/G7Camera/project.yml" "G7Camera/G7Camera.xcodeproj"

env -u FILMY_APP_VARIANT bash -c '
  set -euo pipefail
  root_dir="$1"
  source "$2/app-config.sh"
  [[ "$release_app_variant" == filmy ]]
  [[ "$release_app_target" == FilmyCamera ]]
  [[ "$release_app_project_file" == "$root_dir/FilmyCamera.xcodeproj" ]]
  [[ "$release_app_project_spec" == "$root_dir/project.yml" ]]
  [[ "$release_app_project_relative" == FilmyCamera.xcodeproj ]]
' -- "${root_dir}" "${script_dir}"

if FILMY_APP_VARIANT=unsupported bash -c 'root_dir="$1"; source "$2/app-config.sh"' -- "${root_dir}" "${script_dir}" >/dev/null 2>&1; then
  echo "unsupported app variant unexpectedly passed" >&2
  exit 1
fi

echo "Release app variant configuration checks passed"
