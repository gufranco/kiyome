#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-io.XXXXXX")"
  export SLOW_FACTOR=50
  if [[ "${DISK_TEST_OS}" == "Linux" ]]; then
    export ALLOW_INTERNAL=y
  fi
  SHIMS="${WORK}/shims"
  export SHIMS
  attach 2097152
}

teardown() {
  disk_test_partition_nodes_stop
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

attach() {
  local bytes="$1"
  { head -c "${bytes}" /dev/zero || true; } | LC_ALL=C tr '\000' '\252' >"${WORK}/target.img"
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
  NAME="${DEVICE##*/}"
  fake_install
}

wiping() {
  printf '%s\n' "${DEVICE##*/}" | disk_test_run_env "${1:-}" kiyome "${DEVICE}"
}

picking() {
  printf '%b' "$1" | DISK_INTERACTIVE=1 PASSES=1 disk_test_run kiyome
}

pass_dd() {
  local action="$1"
  disk_test_shim dd "case \"\$*\" in *unique-chunk*of=*${NAME}*) ${action} ;; esac
exec \"\$REAL\" \"\$@\""
}

@test "kiyome falls back to unmounting when the drive refuses to eject" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "Linux has no separate unmount fallback"
  fake_flag eject-fails
  pass_dd "printf 'dd: error writing: Input/output error\\n' >&2; exit 1"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"the drive refused to eject. the volume is unmounted, so nothing else will touch it."* ]]
}

@test "kiyome reads a refused write as write protection" {
  # Arrange
  pass_dd "printf 'dd: /dev/${NAME}: Read-only file system\\n' >&2; exit 1"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"that reads as write protection rather than worn media."* ]]
}

@test "kiyome says when the drive is gone from the bus after a fault" {
  # Arrange
  local gone
  gone="$(fake_dir)/gone"
  pass_dd ": >'${gone}'; printf 'dd: /dev/${NAME}: Device not configured\\n' >&2; exit 1"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"is no longer on the bus, so there is nothing left to eject by software."* ]]
  [[ "${output}" == *"the drive dropped off the bus mid-operation, which is a hardware fault, not bad data."* ]]
}

@test "kiyome stops at once when a transfer is interrupted" {
  # Arrange
  pass_dd "exit 130"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped: interrupted during write chunk"* ]]
}

@test "kiyome does not trust a transfer that moved fewer bytes" {
  # Arrange
  pass_dd "\"\$REAL\" \"\$@\" 2>/dev/null; printf '0+0 records in\\n0+0 records out\\n0 bytes transferred\\n' >&2; exit 0"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"moved 0 of"* ]]
}

@test "kiyome names the bit lines of a byte that read back wrong" {
  # Arrange
  disk_test_shim dd "\"\$REAL\" \"\$@\"; status=\$?
case \"\$*\" in *if=*${NAME}*of=*readback*) printf '\\001' | \"\$REAL\" of=\"\$(printf '%s\\n' \"\$@\" | sed -n 's/^of=//p')\" bs=1 count=1 conv=notrunc 2>/dev/null ;; esac
exit \"\$status\""

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"did not read back as"* ]]
}

@test "kiyome wipes a last chunk shorter than the pattern" {
  # Arrange
  disk_test_detach "${DEVICE}"
  attach 2101248

  # Act
  run wiping "CHUNK_TARGET_MS=1"

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "kiyome stops when a fixed pattern cannot be built" {
  # Arrange
  disk_test_shim tr "[ \"\${2:-}\" = '\\377' ] && exit 1
exec \"\$REAL\" \"\$@\""

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"unable to build the 0xFF reference pattern"* ]]
}

@test "kiyome stops when the unique pattern cannot be built" {
  # Arrange
  disk_test_shim openssl "[ \"\$1\" = enc ] && exit 1
exec \"\$REAL\" \"\$@\""

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"unable to build the unique pattern for chunk 1 of"* ]]
}

@test "kiyome stops when the pattern key cannot be generated" {
  # Arrange
  disk_test_shim openssl "[ \"\$1\" = rand ] && exit 1
exec \"\$REAL\" \"\$@\""

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"unable to generate the key for the unique pattern"* ]]
}

@test "kiyome bypasses the page cache when direct I/O works" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS reads the raw device, which never caches"
  disk_test_shim dd "set -- \$(printf '%s\\n' \"\$@\" | sed '/^iflag=direct\$/d; /^oflag=direct\$/d')
exec \"\$REAL\" \"\$@\""

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Bypassing the page cache so every chunk reaches the media."* ]]
}

@test "kiyome lists only removable disks in the picker" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "macOS reads the internal flag from diskutil"
  unset ALLOW_INTERNAL
  disk_test_shim lsblk "case \"\$*\" in *RM,HOTPLUG,TRAN*${NAME}*) printf '1 0 usb\\n'; exit 0 ;; *RM,HOTPLUG,TRAN*) printf '0 0 sata\\n'; exit 0 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run picking "${NAME}\nn\n"

  # Assert
  [[ "${output}" == *"${DEVICE}"* ]]
}

@test "kiyome says when no removable disk is attached" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "an attached disk image is always removable on macOS"
  unset ALLOW_INTERNAL

  # Act
  run picking "\n"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kiyome: no external or removable disk is attached."* ]]
}

@test "kiyome reports a filesystem it could not create" {
  # Arrange
  disk_test_shim newfs_msdos "exit 1"
  disk_test_shim mkfs.fat "exit 1"

  # Act
  run wiping "CREATE=y"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kiyome: failed to format floppy."* ]]
}

@test "kiyome ejects the drive once the wipe finishes on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "a disk image on macOS ejects through diskutil"
  disk_test_shim eject "exit 0"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Ejected. ${DEVICE} is safe to remove."* ]]
}

@test "kiyome ejects the cartridge after a fault on Linux" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Linux" ]] || skip "a disk image on macOS ejects through diskutil"
  disk_test_shim eject "exit 0"
  pass_dd "printf 'dd: error writing: Input/output error\\n' >&2; exit 1"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Cartridge ejected."* ]]
}

@test "kiyome waits on every transfer when the deadline cap is zero" {
  # Arrange
  local settings="DEADLINE_CAP_MS=0"

  # Act
  run wiping "${settings}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"verifying per-chunk unique data 100%"* ]]
}

@test "kiyome leaves a floppy that stays mounted for the hand to remove" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "Linux ejects every drive the same way"
  fake_identity_as "TEAC USB-FDU"
  fake_flag unmount-fails
  fake_flag mounts-after
  local fake
  fake="$(fake_dir)"
  printf '%s on /Volumes/FAKE (msdos, local)\n' "${DEVICE}" >"${fake}/mounts"
  disk_test_shim sync ": >'${fake}/wiped'"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"${DEVICE} is still mounted. remove the disk by hand once it is idle."* ]]
}
