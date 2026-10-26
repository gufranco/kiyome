#!/usr/bin/env bats

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-timing.XXXXXX")"
  if [[ "${DISK_TEST_OS}" == "Linux" ]]; then
    export ALLOW_INTERNAL=y
  fi
  SHIMS="${WORK}/shims"
  export SHIMS
  DEVICE=""
}

teardown() {
  [[ -z "${DEVICE}" ]] || disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

attach() {
  local bytes="$1"
  { head -c "${bytes}" /dev/zero || true; } | LC_ALL=C tr '\000' '\252' >"${WORK}/target.img"
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
  fake_install
}

wiping() {
  printf 'y\n' | disk_test_run_env "${1:-}" kiyome "${DEVICE}"
}

fail_dd() {
  local match="$1"
  local action="$2"
  disk_test_shim dd "case \"\$*\" in ${match}) ${action} ;; esac
exec \"\$REAL\" \"\$@\""
}

io_error="printf 'dd: error reading: Input/output error\\n' >&2; exit 1"
bus_error="printf 'dd: Device not configured\\n' >&2; exit 1"

@test "a failed read probe leaves the wipe running unwatched" {
  # Arrange
  attach 2097152
  fail_dd "*of=*calibration*bs=65536*" "${io_error}"

  # Act
  run wiping "SLOW_FACTOR=50"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"The read probe failed on the first sectors of"* ]]
  [[ "${output}" == *"That was a read of data this wipe is about to overwrite"* ]]
  [[ "${output}" == *"Speed is not being watched on this disk. Only the byte-for-byte verify decides."* ]]
}

@test "a read probe that loses the bus stops the wipe" {
  # Arrange
  attach 2097152
  fail_dd "*of=*calibration*bs=65536*" "${bus_error}"

  # Act
  run wiping "SLOW_FACTOR=50"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"stopped answering the bus, so this is the drive or the cartridge, not the data."* ]]
}

@test "a Zip disk that cannot be read during the probe is already failing" {
  # Arrange
  attach 2097152
  fake_identity_as "ZIP 100"
  fail_dd "*of=*calibration*bs=65536*" "${io_error}"

  # Act
  run wiping "SLOW_FACTOR=50"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"disk that cannot be read during a light probe is already failing."* ]]
}

@test "a short probe failing past the first stride is reported at its offset" {
  # Arrange
  attach 2097152
  fail_dd "*of=*calibration*bs=4096\ skip=256\ count=1*" "${io_error}"

  # Act
  run wiping "SLOW_FACTOR=50 CALIBRATION_PROBES=2"

  # Assert
  [[ "${output}" == *"The read probe failed at offset 1048576 of"* ]]
}

@test "a long probe failing is reported at its offset" {
  # Arrange
  attach 2097152
  fail_dd "*of=*calibration*bs=4096\ skip=1\ count=128*" "${io_error}"

  # Act
  run wiping "SLOW_FACTOR=50 CALIBRATION_PROBES=2"

  # Assert
  [[ "${output}" == *"The read probe failed at offset 4096 of"* ]]
}

@test "a disk that leaves the bus while being measured stops the wipe" {
  # Arrange
  attach 2097152
  local gone
  gone="$(fake_dir)/gone"
  fail_dd "*of=*calibration*skip=1\ *" "\"\$REAL\" \"\$@\"; : >'${gone}'; exit 0"

  # Act
  run wiping "SLOW_FACTOR=50 CALIBRATION_PROBES=1"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"left the bus while it was being measured."* ]]
}

@test "a disk too small to time is wiped with only the verify watching" {
  # Arrange
  attach 12288

  # Act
  run wiping "SLOW_FACTOR=50"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"is too small to time, so only the byte-for-byte verify will judge it."* ]]
  [[ "${output}" == *"Speed is not being watched on this disk."* ]]
}

@test "a Zip disk that cannot be timed is not wiped blind" {
  # Arrange
  attach 12288
  fake_identity_as "ZIP 100"

  # Act
  run wiping "SLOW_FACTOR=50"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"STOPPED: this disk could not be timed, so nothing would be watching for a stall."* ]]
}

@test "a disk that answers too fast to time is wiped with only the verify watching" {
  # Arrange
  attach 2097152
  disk_test_shim perl "printf '1000000\\n'"

  # Act
  run wiping "SLOW_FACTOR=50"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"answered too fast to time, so only the byte-for-byte verify will judge it."* ]]
}

@test "a clock running backwards is not taken as a measurement" {
  # Arrange
  attach 2097152
  local counter="${WORK}/clock"
  printf '100000000\n' >"${counter}"
  disk_test_shim perl "now=\$(cat '${counter}'); printf '%s\\n' \$((now - 1000)) >'${counter}'; printf '%s\\n' \"\${now}\""

  # Act
  run wiping "SLOW_FACTOR=50"

  # Assert
  [[ "${output}" == *"the clock went backwards while timing"* ]]
}

@test "a Zip probe slower than the ceiling is a head retrying a seek" {
  # Arrange
  attach 2097152
  fake_identity_as "ZIP 100"
  local counter="${WORK}/clock"
  printf '100000000\n' >"${counter}"
  disk_test_shim perl "now=\$(cat '${counter}'); printf '%s\\n' \$((now + 1000)) >'${counter}'; printf '%s\\n' \"\${now}\""

  # Act
  run wiping "SLOW_FACTOR=50 PROBE_CEILING_MS=300"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"which is a drive retrying a seek rather than reading"* ]]
}

@test "a chunk past the stall limit you set stops the wipe" {
  # Arrange
  attach 2097152
  fail_dd "*unique-chunk*of=*" "sleep 2"

  # Act
  run wiping "SLOW_FACTOR=50 STALL_SECONDS=1"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"over the 1s limit you set"* ]]
}

@test "a chunk slower than this disk measured stops the wipe" {
  # Arrange
  attach 2097152
  fail_dd "*unique-chunk*of=*" "sleep 1"

  # Act
  run wiping "SLOW_FACTOR=1"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"allowed by what this disk measured"* ]]
}

@test "a disk that settles at a slower speed stops the wipe" {
  # Arrange
  [[ "${DISK_TEST_OS}" == "Darwin" ]] || skip "loop devices report no seek overhead, so there is no slack to settle in"
  attach 2097152
  fail_dd "*unique-chunk*of=*" "sleep 0.02"

  # Act
  run wiping "SLOW_FACTOR=1"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"has settled at"* ]]
}
