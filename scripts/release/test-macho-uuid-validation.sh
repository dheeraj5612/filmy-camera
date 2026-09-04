#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(mktemp -d -t filmycamera-uuid-test)"
trap 'rm -rf "${work_dir}"' EXIT HUP INT TERM

mock_bin="${work_dir}/bin"
mkdir -p "${mock_bin}"
cat >"${mock_bin}/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "dwarfdump" && "${2:-}" == "--uuid" && -f "${3:-}" ]]
cat "${MOCK_DWARFDUMP_OUTPUT}"
EOF
chmod +x "${mock_bin}/xcrun"

fake_binary="${work_dir}/FilmyCamera"
touch "${fake_binary}"

valid_output="${work_dir}/valid.txt"
cat >"${valid_output}" <<'EOF'
UUID: BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB (arm64e) /tmp/FilmyCamera
UUID: AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA (arm64) /tmp/FilmyCamera
EOF

expected="${work_dir}/expected.txt"
cat >"${expected}" <<'EOF'
arm64:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
arm64e:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
EOF

extract_uuid_function() {
  awk '
    /^macho_uuid_records\(\) \{/ { copying = 1 }
    copying { print }
    copying && /^}$/ { exit }
  ' "$1"
}

for validator in validate-archive.sh validate-ipa.sh; do
  function_file="${work_dir}/${validator}.function"
  extract_uuid_function "${script_dir}/${validator}" >"${function_file}"
  actual="${work_dir}/${validator}.actual"
  PATH="${mock_bin}:${PATH}" MOCK_DWARFDUMP_OUTPUT="${valid_output}" \
    bash -c 'source "$1"; macho_uuid_records "$2" "test executable"' \
      _ "${function_file}" "${fake_binary}" >"${actual}"
  diff -u "${expected}" "${actual}"

  malformed_output="${work_dir}/${validator}.malformed"
  printf '%s\n' 'UUID: not-a-uuid (arm64) /tmp/FilmyCamera' >"${malformed_output}"
  if PATH="${mock_bin}:${PATH}" MOCK_DWARFDUMP_OUTPUT="${malformed_output}" \
    bash -c 'source "$1"; macho_uuid_records "$2" "test executable"' \
      _ "${function_file}" "${fake_binary}" >/dev/null 2>&1; then
    echo "${validator} accepted malformed dwarfdump output" >&2
    exit 1
  fi
done

echo "Mach-O UUID parsing validated"
