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
