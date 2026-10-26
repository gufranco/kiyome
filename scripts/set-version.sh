#!/bin/sh
set -eu

version=${1:?version required}
root=$(cd "$(dirname "$0")/.." && pwd)
core="${root}/lib/core.sh"

if ! grep -q '^KIYOME_VERSION=' "${core}"; then
  printf 'no KIYOME_VERSION assignment found in %s\n' "${core}" >&2
  exit 1
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/kiyome-version-XXXXXX")
sed "s/^KIYOME_VERSION=\".*\"$/KIYOME_VERSION=\"${version}\"/" "${core}" >"${tmp}"
cat "${tmp}" >"${core}"
rm -f "${tmp}"

reported=$("${root}/bin/kiyome" --version)
printf 'version set to %s\n' "${reported}"
