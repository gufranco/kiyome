#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-wipe.XXXXXX")"
  export SLOW_FACTOR=50
  if [[ "${DISK_TEST_OS}" == "Linux" ]]; then
    export ALLOW_INTERNAL=y
  fi
  IMAGE="${WORK}/target.img"
  disk_test_image "${IMAGE}" 4
  DEVICE="$(disk_test_attach "${IMAGE}")"
}

teardown() {
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

disk_wipe_run() {
  printf '%s\n' "${DEVICE##*/}" | disk_test_run kiyome "${DEVICE}"
}

@test "kiyome output matches the recorded golden run" {
  # Arrange
  local name="wipe"

  # Act
  run disk_wipe_run

  # Assert
  [[ "${status}" -eq 0 ]]
  disk_test_matches_golden "${name}" "${output}"
}

@test "the golden normalizer keeps only the finished progress line of a pass" {
  # Arrange
  local raw
  raw="$(printf '%s\n' "Pass 1 of 1, writing 0xAA  12%  86.0 MiB/s  0m01s left" "Pass 1 of 1, writing 0xAA  87%  86.0 MiB/s  0m00s left" "Pass 1 of 1, writing 0xAA 100%  34.7 MiB/s  0m00s left")"

  # Act
  run disk_test_normalize <<<"${raw}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "Pass 1 of 1, writing 0xAA 100%  RATE  T left" ]]
}

@test "kiyome leaves every byte of the device zero" {
  # Arrange
  dd if=/dev/urandom of="${IMAGE}" bs=512 count=16 conv=notrunc 2>/dev/null

  # Act
  run disk_wipe_run

  # Assert
  [[ "${status}" -eq 0 ]]
  local bytes
  bytes="$(disk_test_unique_bytes "${IMAGE}")"
  [[ "${bytes}" == "00" ]]
}

@test "kiyome builds byte patterns under a UTF-8 locale with the system tr" {
  # Arrange
  local search_path="/usr/bin:/bin:${PATH}"

  # Act
  run env PATH="${search_path}" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 sh "${DISK_TESTS_DIR}/call.sh" call_pattern 4096 0xAA

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"aa "* ]]
  [[ "${output}" != *"c2"* ]]
  [[ "${output}" == *"4096"* ]]
}
