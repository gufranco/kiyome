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

@test "kakikomi help prints the usage page on stdout" {
  # Arrange
  local program=kakikomi

  # Act
  run disk_test_run "${program}" help

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "kakikomi - write disk images to removable media, verified chunk by chunk, never mounted" ]]
  [[ "${output}" == *"  kakikomi format [target] [fat32|exfat|fat|floppy] [label]"* ]]
}

@test "kakikomi --help and -h print the same page as help" {
  # Arrange
  local expected
  local short
  expected="$(disk_test_run kakikomi help)"
  short="$(disk_test_run kakikomi -h)"

  # Act
  run disk_test_run kakikomi --help

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "${expected}" ]]
  [[ "${short}" == "${expected}" ]]
}

@test "kakikomi version names the program, its version and the platform" {
  # Arrange
  local version
  local platform
  version="$(sed -n 's/^KAKIKOMI_VERSION="\(.*\)"$/\1/p' "${REPO_DIR}/lib/core.sh")"
  platform="$(uname -sr)"

  # Act
  run disk_test_run kakikomi version

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "kakikomi ${version}" ]]
  [[ "${lines[1]}" == "platform: ${platform}" ]]
}

@test "kakikomi rejects an unknown option with a usage hint" {
  # Arrange
  local option=--frobnicate

  # Act
  run disk_test_run kakikomi "${option}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kakikomi: unknown option '--frobnicate'. run 'kakikomi help' for usage." ]]
}

@test "kakikomi with no arguments and no terminal asks for an image instead of prompting" {
  # Arrange
  local program=kakikomi

  # Act
  run disk_test_run "${program}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kakikomi: no image given. run 'kakikomi help' for usage." ]]
}

@test "kakikomi doctor lists every required tool as ok on a prepared machine" {
  # Arrange
  local program=kakikomi

  # Act
  run disk_test_run "${program}" doctor

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ (^|$'\n')dd\ +ok\  ]]
  [[ "${output}" =~ (^|$'\n')sha256sum\|shasum\ +ok\  ]]
  [[ "${output}" == *"wimlib-imagex"* ]]
}

@test "kakikomi doctor fails and names a missing required tool" {
  # Arrange
  local bin
  bin="$(minimal_path)"

  # Act
  run env PATH="${bin}" "${bin}/sh" "${REPO_DIR}/bin/kakikomi" doctor

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" =~ (^|$'\n')dd\ +missing\ +required ]]
  [[ "${output}" =~ (^|$'\n')xz\ +missing\ +needed\ for\ .xz\ images ]]
}

@test "kakikomi menu runs doctor when asked to check this machine" {
  # Arrange
  local answers='3\n'

  # Act
  run_answering "${answers}" kakikomi

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"What would you like to do?"* ]]
  [[ "${output}" =~ dd\ +ok ]]
}

@test "kakikomi menu rejects a choice it does not offer" {
  # Arrange
  local answers='9\n'

  # Act
  run_answering "${answers}" kakikomi

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: unknown choice '9'. run 'kakikomi help' for usage."* ]]
}

@test "kakikomi gives up after three empty answers for the image" {
  # Arrange
  local answers='1\n\n\n\n'

  # Act
  run_answering "${answers}" kakikomi

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kakikomi: no image given. run 'kakikomi help' for usage."* ]]
}

@test "kakikomi stops when input ends at a prompt" {
  # Arrange
  local answers=''

  # Act
  run_answering "${answers}" kakikomi

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "kakikomi format help prints its own usage page" {
  # Arrange
  local program=kakikomi

  # Act
  run disk_test_run "${program}" format help

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "kakikomi format - quick format a disk: write only the new filesystem's structures" ]]
}

@test "kakikomi format with no disk and no terminal fails with a hint" {
  # Arrange
  local program=kakikomi

  # Act
  run disk_test_run "${program}" format </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kakikomi: no disk given to format. run 'kakikomi help' for usage." ]]
}

@test "kakikomi format rejects an unknown option" {
  # Arrange
  local option=-x

  # Act
  run disk_test_run kakikomi format "${option}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kakikomi: unknown option '-x'. run 'kakikomi help' for usage." ]]
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
  version="$(sed -n 's/^KAKIKOMI_VERSION="\(.*\)"$/\1/p' "${REPO_DIR}/lib/core.sh")"

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
