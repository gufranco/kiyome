#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-flows.XXXXXX")"
  export SLOW_FACTOR=50
  if [[ "${DISK_TEST_OS}" == "Linux" ]]; then
    export ALLOW_INTERNAL=y
  fi
  IMAGE="${WORK}/target.img"
  disk_test_fill "${IMAGE}" 2 '\252'
  DEVICE="$(disk_test_attach "${IMAGE}")"
  NAME="${DEVICE##*/}"
  EXTRA=""
}

teardown() {
  disk_test_detach "${DEVICE}"
  [[ -z "${EXTRA}" ]] || disk_test_detach "${EXTRA}"
  rm -rf "${WORK}"
}

feeding() {
  local answers="$1"
  shift
  printf '%b' "${answers}" | "$@"
}

answering() {
  local answers="$1"
  shift
  printf '%b' "${answers}" | DISK_INTERACTIVE=1 disk_test_run "$@"
}

@test "kiyome rejects a pass count that is not a positive integer" {
  # Arrange
  local settings="PASSES=0"

  # Act
  run disk_test_run_env "${settings}" kiyome "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kiyome: Invalid PASSES value: 0 (must be a positive integer)"* ]]
}

@test "kiyome leaves the disk alone when the confirmation is not y" {
  # Arrange
  local before after
  before="$(disk_test_range_bytes "${IMAGE}" 0 2097152)"

  # Act
  run feeding 'n\n' disk_test_run kiyome "${DEVICE}"
  after="$(disk_test_range_bytes "${IMAGE}" 0 2097152)"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kiyome: warning: Operation cancelled"* ]]
  [[ "${after}" == "${before}" ]]
}

@test "kiyome repeats the patterns for every pass asked" {
  # Arrange
  local settings="PASSES=2"

  # Act
  run feeding 'y\n' disk_test_run_env "${settings}" kiyome "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Pass 2 of 2"* ]]
}

@test "kiyome asks for the disk and the passes in a terminal" {
  # Arrange
  local answers="${NAME}\n1\ny\n"

  # Act
  run answering "${answers}" kiyome
  local bytes
  bytes="$(disk_test_range_bytes "${IMAGE}" 0 2097152)"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Wipe which disk? Number or name: "* ]]
  [[ "${output}" == *"Passes [1]: "* ]]
  [[ "${bytes}" == "00" ]]
}

@test "kiyome does not ask for passes already set" {
  # Arrange
  local answers="${NAME}\ny\n"
  export PASSES=1

  # Act
  run answering "${answers}" kiyome
  run_output="${output}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${run_output}" != *"Passes [1]: "* ]]
}

@test "kiyome wants exactly one disk from the picker" {
  # Arrange
  disk_test_fill "${WORK}/extra.img" 2 '\252'
  EXTRA="$(disk_test_attach "${WORK}/extra.img")"
  local answers="${NAME},${EXTRA##*/}\n"

  # Act
  run answering "${answers}" kiyome

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kiyome: Pick exactly one disk."* ]]
}

@test "kiyome stops when input ends at the passes prompt" {
  # Arrange
  local answers="${NAME}\n"

  # Act
  run answering "${answers}" kiyome

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Passes [1]: "* ]]
}

@test "kiyome leaves a floppy filesystem on a floppy-sized disk with CREATE=y" {
  # Arrange
  local settings="CREATE=y"

  # Act
  run feeding 'y\n' disk_test_run_env "${settings}" kiyome "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Detected media: floppy"* ]]
  [[ "${output}" == *"Formatted as FAT12 (superfloppy)"* ]]
}
