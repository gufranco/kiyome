#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

bats_require_minimum_version 1.5.0

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-json.XXXXXX")"
  export KIYOME_SLOW_FACTOR=50
  if [[ "${KIYOME_TEST_OS}" == "Linux" ]]; then
    export KIYOME_ALLOW_INTERNAL=y
  fi
  IMAGE="${WORK}/target.img"
  disk_test_image "${IMAGE}" 4
  DEVICE="$(disk_test_attach "${IMAGE}")"
}

teardown() {
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

@test "--json prints the wipe's result as one JSON object" {
  # Arrange
  local bytes
  bytes="$(wc -c <"${IMAGE}")"

  # Act
  run --separate-stderr disk_test_run kiyome --json "${DEVICE}" <<<"${DEVICE##*/}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "{\"device\":\"${DEVICE}\",\"bytes\":$((bytes)),\"passes\":1,\"wiped\":true,\"created\":false}" ]]
}

@test "--json reports the number of passes a wipe made" {
  # Arrange
  local bytes
  bytes="$(wc -c <"${IMAGE}")"

  # Act
  run --separate-stderr disk_test_run kiyome --json --passes 2 "${DEVICE}" <<<"${DEVICE##*/}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "{\"device\":\"${DEVICE}\",\"bytes\":$((bytes)),\"passes\":2,\"wiped\":true,\"created\":false}" ]]
}
