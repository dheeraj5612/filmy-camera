#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="${1:-$(cd -P "${script_dir}/../.." && pwd -P)}"

if ! git -C "${repository_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Credential scan failed closed; match details redacted." >&2
  exit 1
fi

private_key_regex="$(printf '%s' '-----BEGIN ' '([A-Z0-9]+ )*' 'PRIVATE KEY-----')"
auth_key_regex="$(printf '%s' 'Auth' 'Key_' '[A-Za-z0-9]{10,}' '\.p8')"
key_id_regex="$(printf '%s' 'FILMY_ASC_KEY' '_ID=' '[A-Za-z0-9]{10}')"
issuer_id_regex="$(printf '%s' 'FILMY_ASC_ISSUER' '_ID=' '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}')"
secret_pattern="${private_key_regex}|${auth_key_regex}|${key_id_regex}|${issuer_id_regex}"
private_key_prefix="-----BEGIN"
private_key_suffix=" PRIVATE KEY-----"

for private_key_modifier in '' OPENSSH RSA EC; do
  private_key_header="${private_key_prefix}${private_key_modifier:+ ${private_key_modifier}}${private_key_suffix}"
  grep -E -q -e "${secret_pattern}" <<<"${private_key_header}" || {
    echo "Credential scan pattern regression for a private-key header; failing closed." >&2
    exit 1
  }
done

set +e
git -C "${repository_root}" -c core.pager=cat grep --quiet -I -E -e "${secret_pattern}" -- \
  >/dev/null 2>&1
secret_scan_status="$?"
set -e

case "${secret_scan_status}" in
  0)
    echo "Potential credential material found in tracked release files; match details redacted." >&2
    exit 1
    ;;
  1)
    ;;
  *)
    echo "Credential scan failed closed; match details redacted." >&2
    exit 1
    ;;
esac
