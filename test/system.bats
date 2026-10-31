#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"
# shellcheck source=test/fakes.bash
source "${BATS_TEST_DIRNAME:-.}/fakes.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-system.XXXXXX")"
  export KIYOME_SLOW_FACTOR=50
  if [[ "${KIYOME_TEST_OS}" == "Linux" ]]; then
    export KIYOME_ALLOW_INTERNAL=y
  fi
  SHIMS="${WORK}/shims"
  export SHIMS
  DEVICE=""
  MOUNTED=""
}

teardown() {
  disk_test_partition_nodes_stop
  if [[ -n "${MOUNTED}" ]]; then
    case "${KIYOME_TEST_OS}" in
    Darwin) hdiutil detach -force "${MOUNTED}" >/dev/null 2>&1 || true ;;
    *) sudo umount "${MOUNTED}" >/dev/null 2>&1 || true ;;
    esac
  fi
  [[ -z "${DEVICE}" ]] || disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

attach_blank() {
  disk_test_fill "${WORK}/target.img" 2 '\252'
  DEVICE="$(disk_test_attach "${WORK}/target.img")"
}

wiping() {
  printf '%s\n' "${DEVICE##*/}" | disk_test_run kiyome "${DEVICE}"
}

declining() {
  printf 'n\n' | disk_test_run kiyome "$1"
}

on_terminal() {
  case "${KIYOME_TEST_OS}" in
  Darwin) script -q /dev/null "$@" </dev/null ;;
  *) script -qec "$(printf '%q ' "$@")" /dev/null </dev/null ;;
  esac
}

@test "a bounded command past its limit is stopped without timeout" {
  # Arrange
  local farm
  farm="$(disk_test_farm timeout gtimeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded 1 sleep 5

  # Assert
  [[ "${status}" -eq 124 ]]
}

@test "a bounded command within its limit keeps its status without timeout" {
  # Arrange
  local farm
  farm="$(disk_test_farm timeout gtimeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded 3 true

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a bounded command without timeout is checked within milliseconds, not once a second" {
  # Arrange
  local farm first second
  farm="$(disk_test_farm timeout gtimeout)"
  disk_test_shim sleep "printf '%s\\n' \"\$1\" >>'${WORK}/sleeps'
exec \"\$REAL\" \"\$@\""

  # Act
  run disk_test_call_path "${SHIMS}:${farm}" disk_bounded 3 perl -e 'select(undef, undef, undef, 1)'

  # Assert
  [[ "${status}" -eq 0 ]]
  {
    read -r first
    read -r second
  } <"${WORK}/sleeps"
  [[ "${first}" == "0.010" ]]
  [[ "${second}" == "0.020" ]]
}

@test "a bounded command uses gtimeout when timeout is missing" {
  # Arrange
  disk_test_shim gtimeout "while [ \"\$#\" -gt 0 ]; do
  case \"\$1\" in
    -k) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
shift
exec \"\$@\""
  local farm
  farm="$(disk_test_farm timeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded 3 true

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a millisecond bound uses gtimeout when timeout is missing" {
  # Arrange
  disk_test_shim gtimeout "while [ \"\$#\" -gt 0 ]; do
  case \"\$1\" in
    -k) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
shift
exec \"\$@\""
  local farm
  farm="$(disk_test_farm timeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded_ms 1500 true

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a millisecond bound falls back to whole seconds without timeout" {
  # Arrange
  local farm
  farm="$(disk_test_farm timeout gtimeout)"

  # Act
  run disk_test_call_path "${farm}" disk_bounded_ms 1500 true

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a transfer that ran for its whole deadline overran it" {
  # Arrange
  disk_test_shim perl "printf '5000\\n'"

  # Act
  run disk_test_call disk_overran 1000 4000

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "a transfer stopped before its deadline did not overrun it" {
  # Arrange
  disk_test_shim perl "printf '5000\\n'"

  # Act
  run disk_test_call disk_overran 1000 4001

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "a transfer without a deadline never overruns" {
  # Arrange
  disk_test_shim perl "printf '5000\\n'"

  # Act
  run disk_test_call disk_overran 1000 0

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "a transfer with an unknown start is not taken as overrun" {
  # Arrange
  local started=""

  # Act
  run disk_test_call disk_overran "${started}" 1000

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "the clock still reads without perl" {
  # Arrange
  disk_test_shim perl "exit 1"

  # Act
  run disk_test_call disk_now_ms

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ ^[0-9]+$ ]]
}

@test "the clock falls back to whole seconds when date has no nanoseconds" {
  # Arrange
  [[ "${KIYOME_TEST_OS}" == "Darwin" ]] || skip "Linux reads /proc/uptime before date"
  disk_test_shim perl "exit 1"
  disk_test_shim date "case \"\$1\" in +%s%N) printf '%sN\\n' \"\$(\"\$REAL\" +%s)\"; exit 0 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run disk_test_call disk_now_ms

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ ^[0-9]+000$ ]]
}

@test "kiyome stops when administrator access is refused" {
  # Arrange
  attach_blank
  disk_test_shim sudo "case \"\$1\" in
  -n) [ \"\${2:-}\" = true ] && exit 1 ;;
  -v) exit 1 ;;
esac
exec \"\$REAL\" \"\$@\""

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Administrator access is required to reach the raw device."* ]]
  [[ "${output}" == *"kiyome: administrator access was not granted."* ]]
}

@test "kiyome continues once administrator access is granted" {
  # Arrange
  attach_blank
  disk_test_shim sudo "case \"\$1\" in
  -n) [ \"\${2:-}\" = true ] && exit 1 ;;
  -v) exit 0 ;;
esac
exec \"\$REAL\" \"\$@\""

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Administrator access is required to reach the raw device."* ]]
}

@test "kiyome resolves a mount point to its whole disk" {
  # Arrange
  disk_test_fat_image "${WORK}/fat.img" 8 KIYOMETEST
  case "${KIYOME_TEST_OS}" in
  Darwin)
    local listing
    listing="$(hdiutil attach "${WORK}/fat.img")"
    DEVICE="${listing%%[[:space:]]*}"
    MOUNTED="${DEVICE}"
    MOUNT_POINT="$(printf '%s\n' "${listing}" | awk -F'\t' '/\/Volumes\// { print $NF; exit }')"
    ;;
  *)
    DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
    disk_test_partition_nodes_start
    MOUNT_POINT="${WORK}/mnt"
    mkdir -p "${MOUNT_POINT}"
    disk_test_wait_partition "${DEVICE}p1"
    sudo mount "${DEVICE}p1" "${MOUNT_POINT}"
    MOUNTED="${MOUNT_POINT}"
    ;;
  esac

  # Act
  run declining "${MOUNT_POINT}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Device: ${DEVICE}"* ]]
}

@test "kiyome unmounts each volume when the whole disk will not unmount on macOS" {
  # Arrange
  [[ "${KIYOME_TEST_OS}" == "Darwin" ]] || skip "Linux unmounts each partition already"
  disk_test_fat_image "${WORK}/fat.img" 8 KIYOMESLICE
  local listing
  listing="$(hdiutil attach "${WORK}/fat.img")"
  DEVICE="${listing%%[[:space:]]*}"
  MOUNTED="${DEVICE}"
  fake_install
  fake_flag unmount-fails

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Disk unmounted"* ]]
}

@test "kiyome unmounts a mounted partition before it wipes on Linux" {
  # Arrange
  [[ "${KIYOME_TEST_OS}" == "Linux" ]] || skip "macOS unmounts the whole disk through diskutil"
  disk_test_fat_image "${WORK}/fat.img" 8 KIYOMEPART
  DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
  disk_test_partition_nodes_start
  mkdir -p "${WORK}/mnt"
  disk_test_wait_partition "${DEVICE}p1"
  sudo mount "${DEVICE}p1" "${WORK}/mnt"
  MOUNTED="${WORK}/mnt"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Disk unmounted"* ]]
}

@test "kiyome unmounts a filesystem on the whole disk before it wipes on Linux" {
  # Arrange
  [[ "${KIYOME_TEST_OS}" == "Linux" ]] || skip "macOS unmounts the whole disk through diskutil"
  disk_test_image "${WORK}/whole.img" 8
  mkfs.fat -F 16 -s 1 -n KIYOMEWHOLE "${WORK}/whole.img" >/dev/null
  DEVICE="$(disk_test_attach "${WORK}/whole.img")"
  mkdir -p "${WORK}/mnt"
  sudo mount "${DEVICE}" "${WORK}/mnt"
  MOUNTED="${WORK}/mnt"

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Disk unmounted"* ]]
}

@test "kiyome refuses a folder that is not a mount point" {
  # Arrange
  local folder="${WORK}/folder"
  mkdir -p "${folder}"

  # Act
  run disk_test_run kiyome "${folder}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "kiyome: no device found for mount point: ${folder}" ]]
}

@test "kiyome resolves a partition to its whole disk" {
  # Arrange
  disk_test_fat_image "${WORK}/fat.img" 8 KIYOMEPART
  DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
  disk_test_partition_nodes_start
  local partition
  case "${KIYOME_TEST_OS}" in
  Darwin) partition="${DEVICE}s1" ;;
  *) partition="${DEVICE}p1" ;;
  esac
  disk_test_wait_partition "${partition}"

  # Act
  run declining "${partition}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Device: ${DEVICE}"* ]]
}

@test "the partition node helper leaves a devtmpfs /dev to the kernel" {
  # Arrange
  [[ "${KIYOME_TEST_OS}" == "Linux" ]] || skip "only Linux tests make partition nodes by hand"
  local shims="${WORK}/devtmpfs-shims"
  mkdir -p "${shims}"
  printf '#!/bin/sh\necho devtmpfs\n' >"${shims}/findmnt"
  chmod +x "${shims}/findmnt"
  PATH="${shims}:${PATH}"

  # Act
  disk_test_partition_nodes_start

  # Assert
  [[ -z "${PARTITION_NODES_PID:-}" ]]
}

@test "a partition node left with an old device number is not ready" {
  # Arrange
  [[ "${KIYOME_TEST_OS}" == "Linux" ]] || skip "only Linux tests make partition nodes by hand"
  disk_test_fat_image "${WORK}/fat.img" 8 KIYOMESTALE
  DEVICE="$(disk_test_attach_partitioned "${WORK}/fat.img")"
  local stale="${WORK}/${DEVICE##*/}p1"
  sudo mknod -m 660 "${stale}" b 7 1048000

  # Act
  run disk_test_partition_ready "${stale}"

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "kiyome refuses a mounted filesystem that is not a block device" {
  # Arrange
  [[ "${KIYOME_TEST_OS}" == "Linux" ]] || skip "macOS reports a device node for every mounted volume"

  # Act
  run disk_test_run kiyome /dev/shm </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kiyome: device not found or invalid: "* ]]
}

@test "kiyome needs openssl for the per-chunk pattern" {
  # Arrange
  attach_blank
  local farm
  farm="$(disk_test_farm openssl)"

  # Act
  run disk_test_run_path "${farm}" kiyome "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"kiyome: openssl is required to build the per-chunk unique pattern"* ]]
}

@test "doctor marks a missing required tool and a missing pair" {
  # Arrange
  local farm
  farm="$(disk_test_farm dd sha256sum shasum)"

  # Act
  run disk_test_run_path "${farm}" kiyome doctor

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" =~ (^|$'\n')dd\ +missing\ +required ]]
  [[ "${output}" =~ (^|$'\n')sha256sum\|shasum\ +missing\ +validates ]]
}

@test "kiyome runs when called by name from PATH" {
  # Arrange
  local bin="${REPO_DIR}/bin"
  local -a shell_words
  local version
  read -r -a shell_words <<<"${KIYOME_TEST_SHELL:-sh}"
  version="$(sed -n 's/^KIYOME_VERSION="\(.*\)"$/\1/p' "${REPO_DIR}/lib/core.sh")"

  # Act
  run bash -c 'cd "$1" && shift && PATH="$PWD:$PATH" "$@" kiyome version' _ "${bin}" "${shell_words[@]}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" == "kiyome ${version}" ]]
}

@test "kiyome goes on when the drive gives no write-protect answer" {
  # Arrange
  attach_blank
  fake_install
  printf '<string>unknown</string>\n' >"$(fake_dir)/plist/WritableMedia"
  disk_test_shim blockdev "case \"\$*\" in *--getro*) printf 'unknown\\n'; exit 0 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run wiping

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" != *"write protected"* ]]
}

@test "the sector size falls back to 512 bytes when the drive does not say" {
  # Arrange
  attach_blank
  fake_install
  printf '/Device Block Size:/d\n' >"$(fake_dir)/info.sed"
  disk_test_shim blockdev "case \"\$*\" in *--getss*) exit 1 ;; esac
exec \"\$REAL\" \"\$@\""

  # Act
  run disk_test_call disk_sector_bytes "${DEVICE}"

  # Assert
  [[ "${output}" == "512" ]]
}

@test "progress redraws one line on a terminal" {
  # Arrange
  local -a shell_words
  read -r -a shell_words <<<"${KIYOME_TEST_SHELL:-sh}"
  local search_path
  search_path="$(disk_test_path)"

  # Act
  run on_terminal env PATH="${search_path}" "${shell_words[@]}" "${KIYOME_TESTS_DIR}/call.sh" disk_progress "Pass 1 of 1, writing 0xAA" 1048576 1048576 0

  # Assert
  [[ "${output}" == *"Pass 1 of 1, writing 0xAA 100%"* ]]
}
