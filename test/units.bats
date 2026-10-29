#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

@test "a 1474560 byte disk is floppy media" {
  # Arrange
  local size=1474560

  # Act
  run disk_test_call disk_media_class "${size}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "floppy" ]]
}

@test "a 104857600 byte disk is zip media" {
  # Arrange
  local size=104857600

  # Act
  run disk_test_call disk_media_class "${size}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "zip" ]]
}

@test "a 1073741824 byte disk is small media" {
  # Arrange
  local size=1073741824

  # Act
  run disk_test_call disk_media_class "${size}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "small" ]]
}

@test "a 17179869184 byte disk is medium media" {
  # Arrange
  local size=17179869184

  # Act
  run disk_test_call disk_media_class "${size}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "medium" ]]
}

@test "a 68719476736 byte disk is large media" {
  # Arrange
  local size=68719476736

  # Act
  run disk_test_call disk_media_class "${size}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "large" ]]
}

@test "a partition node gains p after a trailing digit" {
  # Arrange
  local disk=/dev/loop3

  # Act
  run disk_test_call disk_partition_node "${disk}"

  # Assert
  [[ "${output}" == "/dev/loop3p1" ]]
}

@test "a partition node gains only a number after a letter" {
  # Arrange
  local disk=/dev/sdb

  # Act
  run disk_test_call disk_partition_node "${disk}"

  # Assert
  [[ "${output}" == "/dev/sdb1" ]]
}

@test "IOMEGA ZIP 100 is zip" {
  # Arrange
  local identity="IOMEGA ZIP 100"

  # Act
  run disk_test_call disk_family_of "${identity}"

  # Assert
  [[ "${output}" == "zip" ]]
}

@test "MATSHITA LS-120 is superdisk" {
  # Arrange
  local identity="MATSHITA LS-120"

  # Act
  run disk_test_call disk_family_of "${identity}"

  # Assert
  [[ "${output}" == "superdisk" ]]
}

@test "IOMEGA JAZ 2GB is jaz" {
  # Arrange
  local identity="IOMEGA JAZ 2GB"

  # Act
  run disk_test_call disk_family_of "${identity}"

  # Assert
  [[ "${output}" == "jaz" ]]
}

@test "TEAC USB-FDU is floppy" {
  # Arrange
  local identity="TEAC USB-FDU"

  # Act
  run disk_test_call disk_family_of "${identity}"

  # Assert
  [[ "${output}" == "floppy" ]]
}

@test "IOMEGA POCKETZIP is pocketzip" {
  # Arrange
  local identity="IOMEGA POCKETZIP"

  # Act
  run disk_test_call disk_family_of "${identity}"

  # Assert
  [[ "${output}" == "pocketzip" ]]
}

@test "SANDISK ULTRA is no family" {
  # Arrange
  local identity="SANDISK ULTRA"

  # Act
  run disk_test_call disk_family_of "${identity}"

  # Assert
  [[ "${output}" == "" ]]
}

@test "dd: /dev/rdisk9: Device not configured is a bus error" {
  # Arrange
  local detail="dd: /dev/rdisk9: Device not configured"

  # Act
  run disk_test_call disk_error_class "${detail}"

  # Assert
  [[ "${output}" == "bus" ]]
}

@test "dd: error writing: Input/output error is a media error" {
  # Arrange
  local detail="dd: error writing: Input/output error"

  # Act
  run disk_test_call disk_error_class "${detail}"

  # Assert
  [[ "${output}" == "media" ]]
}

@test "dd: invalid number is a other error" {
  # Arrange
  local detail="dd: invalid number"

  # Act
  run disk_test_call disk_error_class "${detail}"

  # Assert
  [[ "${output}" == "other" ]]
}

@test "a duration under a second prints in milliseconds" {
  # Arrange
  local ms=250

  # Act
  run disk_test_call disk_duration "${ms}"

  # Assert
  [[ "${output}" == "250ms" ]]
}

@test "a duration over a second prints in whole seconds" {
  # Arrange
  local ms=4200

  # Act
  run disk_test_call disk_duration "${ms}"

  # Assert
  [[ "${output}" == "4s" ]]
}

@test "sizes print in binary units" {
  # Arrange
  local bytes=1572864

  # Act
  run disk_test_call disk_human "${bytes}"

  # Assert
  [[ "${output}" == "1.5 MiB" ]]
}

@test "a picked number maps to the listed disk at that position" {
  # Arrange
  local listed=$'/dev/disk4\n/dev/disk5'

  # Act
  run disk_test_call disk_pick_one 2 "${listed}" 2

  # Assert
  [[ "${output}" == "/dev/disk5" ]]
}

@test "a picked name maps to the listed disk" {
  # Arrange
  local listed=$'/dev/disk4\n/dev/disk5'

  # Act
  run disk_test_call disk_pick_one disk4 "${listed}" 2

  # Assert
  [[ "${output}" == "/dev/disk4" ]]
}

@test "a pick that names no listed disk is refused" {
  # Arrange
  local listed=$'/dev/disk4\n/dev/disk5'

  # Act
  run disk_test_call disk_pick_one disk9 "${listed}" 2

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: not a listed number or disk: disk9." ]]
}

@test "a failure report repeats what dd said and clears it" {
  # Arrange
  local detail="dd: error reading: Input/output error"

  # Act
  run disk_test_call call_report_failure "${detail}" "the read probe failed."

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "kiyome: the read probe failed." ]]
  [[ "${lines[1]}" == "kiyome: dd said: ${detail}" ]]
  [[ "${#lines[@]}" -eq 2 ]]
}

@test "logged lines skip blanks and keep their level" {
  # Arrange
  local text=$'first\n\nsecond'

  # Act
  run disk_test_call disk_log_lines disk_warning "${text}"

  # Assert
  [[ "${output}" == $'kiyome: warning: first\nkiyome: warning: second' ]]
}

@test "a reference longer than the chunk is trimmed to the chunk" {
  # Arrange
  local pattern=8192

  # Act
  run disk_test_call call_exact_reference "${pattern}" 512

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "512" ]]
}

@test "a working directory that cannot be made stops with a message" {
  # Arrange
  export TMPDIR="${BATS_TMPDIR:-/tmp}/kiyome-missing-${RANDOM}/deeper"

  # Act
  run disk_test_call disk_make_tmpdir kiyome

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kiyome: unable to create a working directory."* ]]
}

@test "an unknown system cannot release a disk" {
  # Arrange
  export KIYOME_OS=FreeBSD

  # Act
  run disk_test_call disk_release /dev/da0

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "an unknown system treats every disk as internal" {
  # Arrange
  export KIYOME_OS=FreeBSD

  # Act
  run disk_test_call disk_is_internal /dev/da0

  # Assert
  [[ "${status}" -eq 0 ]]
}
