#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-create.XXXXXX")"
  IMAGE="${WORK}/target.img"
  disk_test_image "${IMAGE}" 64
  DEVICE="$(disk_test_attach_partitioned "${IMAGE}")"
  disk_test_partition_nodes_start
}

teardown() {
  disk_test_partition_nodes_stop
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

@test "a zip-sized disk gets a FAT16 filesystem named ZIP" {
  # Arrange
  local size=104857600

  # Act
  run disk_test_call disk_create_partition "${DEVICE}" "${size}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Detected media: zip"* ]]
  [[ "${output}" == *"Partition created (FAT16)"* ]]
}

@test "a small disk gets a FAT16 filesystem" {
  # Arrange
  local size=1073741824

  # Act
  run disk_test_call disk_create_partition "${DEVICE}" "${size}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Detected media: small"* ]]
  [[ "${output}" == *"Partition created (FAT16)"* ]]
}

@test "a medium disk gets a FAT32 filesystem" {
  # Arrange
  local size=17179869184

  # Act
  run disk_test_call disk_create_partition "${DEVICE}" "${size}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Detected media: medium"* ]]
  [[ "${output}" == *"Partition created (FAT32)"* ]]
}

@test "a large disk gets an exFAT filesystem" {
  # Arrange
  local size=68719476736

  # Act
  run disk_test_call disk_create_partition "${DEVICE}" "${size}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Detected media: large"* ]]
  [[ "${output}" == *"Partition created (ExFAT)"* ]]
}
