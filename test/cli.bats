#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-cli.XXXXXX")"
}

teardown() {
  rm -rf "${WORK}"
}

answering() {
  local answers="$1"
  shift
  printf '%b' "${answers}" | DISK_INTERACTIVE=1 disk_test_run "$@"
}

run_answering() {
  run answering "$@"
}

minimal_path() {
  local bin="${WORK}/bin"
  local tool
  local found
  mkdir -p "${bin}"
  for tool in sh uname awk sed tr wc cat dirname; do
    found="$(command -v "${tool}")"
    ln -s "${found}" "${bin}/${tool}"
  done
  printf '%s' "${bin}"
}

@test "kiyome help prints the usage page on stdout" {
  # Arrange
  local program=kiyome

  # Act
  run disk_test_run "${program}" help

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "kiyome - overwrite a disk with five verified patterns, reporting any bad bit line" ]]
}

@test "kiyome version names the program and its version" {
  # Arrange
  local version
  version="$(sed -n 's/^KIYOME_VERSION="\(.*\)"$/\1/p' "${REPO_DIR}/lib/core.sh")"

  # Act
  run disk_test_run kiyome --version

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "kiyome ${version}" ]]
}

@test "kiyome rejects an unknown option with a usage hint" {
  # Arrange
  local option=--fast

  # Act
  run disk_test_run kiyome "${option}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: unknown option '--fast'. run 'kiyome help' for usage." ]]
}

@test "kiyome with no arguments and no terminal fails with a hint" {
  # Arrange
  local program=kiyome

  # Act
  run disk_test_run "${program}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: no disk given. run 'kiyome help' for usage." ]]
}

@test "kiyome doctor checks openssl instead of the image tools" {
  # Arrange
  local program=kiyome

  # Act
  run disk_test_run "${program}" doctor

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ (^|$'\n')openssl\ +ok\  ]]
  [[ "${output}" != *"wimlib-imagex"* ]]
}

@test "kiyome doctor fails and names a missing openssl" {
  # Arrange
  local bin
  bin="$(minimal_path)"

  # Act
  run env PATH="${bin}" "${bin}/sh" "${REPO_DIR}/bin/kiyome" doctor

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" =~ (^|$'\n')openssl\ +missing\ +builds\ the\ per-chunk\ unique\ pattern ]]
}

@test "kiyome names an option that is missing its value" {
  # Arrange
  local option=--passes

  # Act
  run disk_test_run kiyome "${option}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: option '--passes' needs a value. run 'kiyome help' for usage." ]]
}

@test "kiyome refuses a value given to an option that takes none" {
  # Arrange
  local option=--create=yes

  # Act
  run disk_test_run kiyome "${option}" /dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: option '--create' takes no value. run 'kiyome help' for usage." ]]
}

@test "kiyome names an unknown option written as name=value" {
  # Arrange
  local option=--speed=fast

  # Act
  run disk_test_run kiyome "${option}" /dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: unknown option '--speed'. run 'kiyome help' for usage." ]]
}

@test "kiyome checks the pass count given as name=value before touching any disk" {
  # Arrange
  local option=--passes=many

  # Act
  run disk_test_run kiyome "${option}" "${WORK}/missing"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: --passes must be a whole number of 1 or more, got: many" ]]
}

@test "kiyome lets an option on the command line win over the environment" {
  # Arrange
  local settings="PASSES=0"

  # Act
  run disk_test_run_env "${settings}" kiyome --passes 1 "${WORK}/missing"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: not a device or mount point: ${WORK}/missing" ]]
}

@test "kiyome treats everything after -- as the disk" {
  # Arrange
  local disk=--odd-name

  # Act
  run disk_test_run kiyome -- "${disk}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: not a device or mount point: --odd-name" ]]
}

@test "kiyome refuses a second disk" {
  # Arrange
  local second=/dev/second

  # Act
  run disk_test_run kiyome /dev/first "${second}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: unexpected extra argument '/dev/second'. run 'kiyome help' for usage." ]]
}

help_options() {
  local page
  page="$(disk_test_run kiyome help)" || return 1
  awk '/^  --/ { for (i = 1; i <= NF; i++) if (match($i, /^--[a-z0-9][a-z0-9-]*/)) { name = substr($i, RSTART, RLENGTH); if (!seen[name]++) print name } }' <<<"${page}"
}

option_drift() {
  local option name man_form missing="" listed completed
  listed="$(help_options)" || return 1
  completed="$(grep -oE -- "--[a-z0-9][a-z0-9-]*" "${REPO_DIR}/completions/kiyome.bash")" || return 1
  for option in ${listed}; do
    name="${option#--}"
    man_form="\\-\\-${name//-/\\-}"
    grep -qF -- "${man_form}" "${REPO_DIR}/man/kiyome.1" || missing="${missing} man:${option}"
    grep -qE -- "(^|[ \"])${option}( |\"|$)" "${REPO_DIR}/completions/kiyome.bash" || missing="${missing} bash:${option}"
    grep -qE -- "'\\*?${option}\\[" "${REPO_DIR}/completions/_kiyome" || missing="${missing} zsh:${option}"
    grep -qE -- "-l ${name} " "${REPO_DIR}/completions/kiyome.fish" || missing="${missing} fish:${option}"
  done
  for option in ${completed}; do
    grep -qx -- "${option}" <<<"${listed}" || missing="${missing} help:${option}"
  done
  printf '%s' "${missing}"
}

@test "kiyome help, man page and completions list the same options" {
  # Arrange
  local expected=""

  # Act
  run option_drift

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "${expected}" ]]
}

@test "kiyome man page passes mandoc lint" {
  # Arrange
  local page="${REPO_DIR}/man/kiyome.1"

  # Act
  run mandoc -T lint "${page}"

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "kiyome accepts every switch before the disk" {
  # Arrange
  local missing="${WORK}/missing"

  # Act
  run disk_test_run kiyome --allow-internal --create "${missing}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: not a device or mount point: ${missing}" ]]
}

@test "kiyome rejects an unknown short option with a usage hint" {
  # Arrange
  local option=-x

  # Act
  run disk_test_run kiyome "${option}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: unknown option '-x'. run 'kiyome help' for usage." ]]
}
