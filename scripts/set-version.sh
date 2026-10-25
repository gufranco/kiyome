#!/bin/sh
set -eu

version=${1:?version required}
root=$(cd "$(dirname "$0")/.." && pwd)
core="${root}/lib/core.sh"

if ! grep -q '^KAKIKOMI_VERSION=' "${core}"; then
  printf 'no KAKIKOMI_VERSION assignment found in %s\n' "${core}" >&2
  exit 1
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/kakikomi-version-XXXXXX")
sed "s/^KAKIKOMI_VERSION=\".*\"$/KAKIKOMI_VERSION=\"${version}\"/" "${core}" >"${tmp}"
cat "${tmp}" >"${core}"
rm -f "${tmp}"

reported=$("${root}/bin/kakikomi" --version)
printf 'version set to %s\n' "${reported}"
