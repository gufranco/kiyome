#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
duplicates=$(cat "${root}"/bin/kiyome "${root}"/lib/*.sh |
  sed -n 's/^\([a-z_][a-z0-9_]*\)() {$/\1/p' | sort | uniq -d)
if [ -n "${duplicates}" ]; then
  printf 'function defined more than once:\n%s\n' "${duplicates}" >&2
  exit 1
fi

unprefixed=$(cat "${root}"/bin/kiyome "${root}"/lib/*.sh |
  grep -oE '[$][{]?[A-Z][A-Z0-9_]*' | sed 's/^[$][{]*//' | sort -u |
  grep -vE '^(DISK|KIYOME)_' | grep -vxE 'HOME|PATH|TMPDIR|NF|ZSH_VERSION' || true)
if [ -n "${unprefixed}" ]; then
  printf 'environment variable without the KIYOME_ prefix:\n%s\n' "${unprefixed}" >&2
  exit 1
fi

scrub="for disk_inherited in \$(env | sed -n 's/^\\(DISK_[A-Za-z0-9_]*\\)=.*/\\1/p'); do"
if ! grep -qF "${scrub}" "${root}/bin/kiyome"; then
  printf 'bin/kiyome must clear every inherited DISK_ variable before it starts\n' >&2
  exit 1
fi
