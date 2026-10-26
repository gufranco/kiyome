#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

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

@test "a failed erase is reported on macOS" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "Linux partitions with its own tools"
  SHIMS="${WORK}/shims"
  disk_test_shim diskutil "[ \"\$1\" = eraseDisk ] && exit 1
exec \"\$REAL\" \"\$@\""

  # Act
  run disk_test_call disk_create_partition "${DEVICE}" 1073741824

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kiyome: Failed to create partition"* ]]
}

@test "a missing partitioner is named on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS partitions with diskutil"
  local farm
  farm="$(disk_test_farm sfdisk)"

  # Act
  run disk_test_call_path "${farm}" disk_create_partition "${DEVICE}" 1073741824

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"sfdisk is not installed. Install the fdisk package."* ]]
}

@test "a missing formatter is named on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS formats with diskutil"
  local farm
  farm="$(disk_test_farm mkfs.fat)"

  # Act
  run disk_test_call_path "${farm}" disk_create_partition "${DEVICE}" 1073741824

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"mkfs.fat is not installed."* ]]
}

@test "a missing floppy formatter is named on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS formats floppies with newfs_msdos"
  local farm
  farm="$(disk_test_farm mkfs.fat)"

  # Act
  run disk_test_call_path "${farm}" disk_create_partition "${DEVICE}" 1474560

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"mkfs.fat is not installed. Install the dosfstools package."* ]]
}

@test "a partition table that cannot be written is reported on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS partitions with diskutil"
  SHIMS="${WORK}/shims"
  disk_test_shim sfdisk "exit 1"

  # Act
  run disk_test_call disk_create_partition "${DEVICE}" 1073741824

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Failed to create partition table"* ]]
}

@test "a partition that never appears is reported on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS creates the partition with the filesystem"
  disk_test_partition_nodes_stop
  disk_test_detach "${DEVICE}"
  DEVICE="$(disk_test_attach "${IMAGE}")"
  sudo rm -f "${DEVICE}p1"
  disk_test_shim sfdisk "exit 0"

  # Act
  run disk_test_call disk_create_partition "${DEVICE}" 1073741824

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Partition ${DEVICE}p1 did not appear"* ]]
}

@test "a filesystem that cannot be made is reported on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS formats with diskutil"
  SHIMS="${WORK}/shims"
  disk_test_shim mkfs.fat "exit 1"

  # Act
  run disk_test_call disk_create_partition "${DEVICE}" 1073741824

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Failed to format partition"* ]]
}
