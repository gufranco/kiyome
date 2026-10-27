#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-hardware.XXXXXX")"
  export SLOW_FACTOR=50
  if [[ "${DISK_TEST_OS}" == "Linux" ]]; then
    export ALLOW_INTERNAL=y
  fi
  IMAGE="${WORK}/target.img"
  disk_test_fill "${IMAGE}" 2 '\252'
  DEVICE="$(disk_test_attach "${IMAGE}")"
  NAME="${DEVICE##*/}"
  SHIMS="${WORK}/shims"
  export SHIMS
  fake_install
}

teardown() {
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

wiping() {
  printf '%s\n' "${DEVICE##*/}" | disk_test_run kiyome "${DEVICE}"
}

@test "kiyome stops on media the drive reports as read-only" {
  # Arrange
  fake_read_only

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"is write protected, so nothing on it can be erased."* ]]
  [[ "${output}" == *"the drive reports this media as read-only."* ]]
  [[ "${output}" == *"Release the write-protect switch or lock on the device"* ]]
}

@test "kiyome tells how to unprotect a floppy" {
  # Arrange
  fake_read_only
  fake_identity_as "TEAC USB-FDU"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Cover the square hole on the corner of the disk"* ]]
}

@test "kiyome tells how to unprotect a Zip cartridge" {
  # Arrange
  fake_read_only
  fake_identity_as "ZIP 100"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Unlock the cartridge, through the Iomega tools or its write-protect tab"* ]]
}

@test "kiyome stops when the disk size cannot be read" {
  # Arrange
  fake_size_unknown

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kiyome: unable to determine disk size for ${DEVICE}."* ]]
}

@test "kiyome skips a partial last sector" {
  # Arrange
  fake_size_bytes 2097252

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"device size is not a whole number of sectors. skipping the last 100 bytes."* ]]
}

@test "kiyome stops when the drive refuses to eject after a fault" {
  # Arrange
  fake_flag eject-fails
  fake_flag unmount-fails
  disk_test_shim dd "case \"\$*\" in *unique-chunk*of=*${NAME}*) printf 'dd: error writing: Input/output error\\n' >&2; exit 1 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"cut power to the drive before doing anything else with it."* ]]
}

@test "kiyome says the wipe finished when only the final eject fails" {
  # Arrange
  fake_flag eject-fails

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"did not eject. the wipe already finished, so remove it once the light stops."* ]]
}

@test "kiyome leaves a floppy for the hand to remove" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "Linux ejects every drive the same way"
  fake_identity_as "TEAC USB-FDU"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. This drive has no software eject, so take the disk out now."* ]]
}

@test "kiyome stops when the disk stays mounted" {
  # Arrange
  fake_flag unmount-fails
  printf '%s on /Volumes/FAKE (msdos, local)\n' "${DEVICE}" >"$(fake_dir)/mounts"
  printf '/mnt/fake\n' >>"$(fake_dir)/mounts"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"disk is still mounted, so writing to it would corrupt the mounted volume"* ]]
}

@test "kiyome stops when the mount state cannot be read" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS reads the mount table directly"
  fake_flag mount-state-fails

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"unable to read the mount state of ${DEVICE}, so this stops here"* ]]
}

@test "kiyome refuses a path that is neither a device nor a mount point" {
  # Arrange
  local file="${WORK}/not-a-disk"
  : >"${file}"

  # Act
  run disk_test_run kiyome "${file}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: not a device or mount point: ${file}" ]]
}
