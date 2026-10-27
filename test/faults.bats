#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-faults.XXXXXX")"
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
}

teardown() {
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

wiping() {
  printf '%s\n' "${DEVICE##*/}" | disk_test_run_env "${1:-}" kiyome "${DEVICE}"
}

fake_identity() {
  local model="$1"
  if [[ "${DISK_TEST_OS}" == "Darwin" ]]; then
    disk_test_shim diskutil "if [ \"\$1\" = info ] && [ \"\$2\" = -plist ]; then
  \"\$REAL\" \"\$@\" | awk -v model='${model}' 'swap { sub(/<string>[^<]*<\\/string>/, \"<string>\" model \"</string>\"); swap = 0 } /<key>MediaName<\\/key>/ { swap = 1 } { print }'
  exit 0
fi
exec \"\$REAL\" \"\$@\""
  else
    disk_test_shim lsblk "case \"\$*\" in
  *VENDOR*) printf 'IOMEGA\\n' ;;
  *MODEL*) printf '%s\\n' '${model}' ;;
  *) exec \"\$REAL\" \"\$@\" ;;
esac"
  fi
}

fake_dd() {
  local condition="$1"
  local action="$2"
  disk_test_shim dd "target=''
for arg in \"\$@\"; do
  case \"\$arg\" in
    of=*${NAME}) target=write ;;
    if=*${NAME}) target=read ;;
  esac
done
if [ -n \"\$target\" ] && ${condition}; then
  ${action}
fi
exec \"\$REAL\" \"\$@\""
}

first_sector='case " $* " in *" seek=0 count=1 "*) true ;; *) false ;; esac'
pass_write='case "$*" in *unique-chunk*) true ;; *) false ;; esac'
probe_write='case "$*" in *pattern-*) true ;; *) false ;; esac'

@test "kiyome stops after three failed attempts at the same chunk" {
  # Arrange
  fake_dd "[ \"\$target\" = write ] && ${pass_write}" "printf 'dd: error writing: Input/output error\n' >&2; exit 1"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"failed 3 times at offset"* ]]
  [[ "${output}" == *"dd said: dd: error writing: Input/output error"* ]]
}

@test "kiyome calls a media error on a Zip disk the click of death" {
  # Arrange
  fake_identity "ZIP 100"
  fake_dd "[ \"\$target\" = write ] && ${pass_write}" "printf 'dd: error writing: Input/output error\n' >&2; exit 1"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Handling this as fragile media"* ]]
  [[ "${output}" == *"did not come back clean at offset"* ]]
  [[ "${output}" == *"this is the click of death"* ]]
}

@test "kiyome reports a chunk that only settled on a retry" {
  # Arrange
  local once="${WORK}/failed-once"
  fake_dd "[ \"\$target\" = write ] && ${pass_write} && [ ! -e '${once}' ]" ": >'${once}'; printf 'dd: error writing: Input/output error\n' >&2; exit 1"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"needed 2 attempts at offset"* ]]
  [[ "${output}" == *"chunks only settled on a retry. this media is wearing out."* ]]
}

@test "kiyome stops at once when the drive leaves the bus" {
  # Arrange
  fake_dd "[ \"\$target\" = write ] && ${pass_write}" "printf 'dd: /dev/${NAME}: Device not configured\n' >&2; exit 1"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped answering at offset"* ]]
}

@test "kiyome stops a transfer that runs past its deadline" {
  # Arrange
  local settings="DEADLINE_CAP_MS=2000"
  fake_dd "[ \"\$target\" = write ] && ${pass_write}" "sleep 5"

  # Act
  run wiping "${settings}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"went silent for"* ]]
  [[ "${output}" == *"the drive stopped answering mid-transfer"* ]]
}

@test "kiyome stops when the disk fails while it is being measured" {
  # Arrange
  fake_dd "[ \"\$target\" = write ] && ${probe_write}" "printf 'dd: error writing: Input/output error\n' >&2; exit 1"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"the write probe failed on the first sectors of"* ]]
  [[ "${output}" == *"stopped: the disk failed while being measured, before the wipe started"* ]]
}

@test "kiyome refuses media whose writes silently do not land" {
  # Arrange
  fake_dd "[ \"\$target\" = write ] && ${first_sector}" "set -- \$(printf '%s\n' \"\$@\" | sed 's|^of=.*|of=/dev/null|; /^seek=/d'); exec \"\$REAL\" \"\$@\""

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"is write protected, so nothing on it can be erased."* ]]
  [[ "${output}" == *"the drive accepted a test write and the media kept its previous contents."* ]]
}

@test "kiyome stops when the drive leaves the bus during the test write" {
  # Arrange
  fake_dd "[ \"\$target\" = write ] && ${first_sector}" "printf 'dd: /dev/${NAME}: Device not configured\n' >&2; exit 1"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped answering during the single-sector write test"* ]]
}
