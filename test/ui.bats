#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/disk-ui.XXXXXX")"
  export KIYOME_SLOW_FACTOR=50
  if [[ "${KIYOME_TEST_OS}" == "Linux" ]]; then
    export KIYOME_ALLOW_INTERNAL=y
  fi
  IMAGE="${WORK}/target.img"
  disk_test_fill "${IMAGE}" 2 '\252'
  DEVICE="$(disk_test_attach "${IMAGE}")"
  NAME="${DEVICE##*/}"
  unset KODOUGU_THEME KODOUGU_ACCENT KIYOME_THEME NO_COLOR
  export KIYOME_TEST_GUM=1
  export KIYOME_TEST_GUM_LOG="${WORK}/gum.log"
  export KIYOME_TEST_GUM_ANSWERS="${WORK}/answers"
  export KIYOME_INTERACTIVE=1
  : >"${KIYOME_TEST_GUM_LOG}"
}

teardown() {
  disk_test_detach "${DEVICE}"
  rm -rf "${WORK}"
}

answers() {
  printf '%s\n' "$@" >"${KIYOME_TEST_GUM_ANSWERS}"
}

never_called() {
  if grep -q -F -- "$1" "${KIYOME_TEST_GUM_LOG}"; then
    return 1
  fi
}

called() {
  grep -q -F -- "$1" "${KIYOME_TEST_GUM_LOG}"
}

untouched() {
  local bytes
  bytes="$(disk_test_range_bytes "${IMAGE}" 0 2097152)"
  [[ "${bytes}" == "aa" ]]
}

@test "the disk is picked from a gum list, its name typed in a danger box, and wiped" {
  # Arrange
  local bar bytes
  bar="$(printf '\342\224\201')"
  answers "${DEVICE}" "1" "${NAME}"

  # Act
  run disk_test_run kiyome </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  bytes="$(disk_test_range_bytes "${IMAGE}" 0 2097152)"
  [[ "${bytes}" == "00" ]]
  [[ "${output}" == *"overwrite a disk with five verified patterns"* ]]
  [[ "${output}" == *"Device:"*"${DEVICE}"* ]]
  [[ "${output}" == *"${bar}"* ]]
  [[ "${output}" == *"Wiped ${DEVICE}: every byte of every pattern read back as written."* ]]
  called "choose --header Wipe which disk?"
  called "input --header Passes"
  called "--border thick"
  called "input --header Type ${NAME} to erase"
}

@test "an empty passes answer runs one pass" {
  # Arrange
  answers "${DEVICE}" "" "${NAME}"

  # Act
  run disk_test_run kiyome </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"1 pass of unique data"* ]]
  called "input --header Passes --placeholder 1"
}

@test "passes already set are not asked for" {
  # Arrange
  answers "${DEVICE}" "${NAME}"
  export KIYOME_PASSES=1

  # Act
  run disk_test_run kiyome </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  never_called "input --header Passes"
}

@test "a cancelled disk pick wipes nothing" {
  # Arrange
  answers "<cancel>"

  # Act
  run disk_test_run kiyome </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  untouched
}

@test "a wrong name typed into gum wipes nothing" {
  # Arrange
  answers "disk999"

  # Act
  run disk_test_run kiyome "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"WARN kiyome: cancelled, nothing was touched."* ]]
  untouched
}

@test "a cancelled typed name wipes nothing" {
  # Arrange
  answers "<cancel>"

  # Act
  run disk_test_run kiyome "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"cancelled, nothing was touched."* ]]
  untouched
}

@test "doctor draws its rows in a table" {
  # Arrange
  local expected="openssl"

  # Act
  run disk_test_run kiyome doctor </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Tool"*"State"*"Detail"* ]]
  [[ "${output}" == *"${expected}"* ]]
  [[ "${output}" == *"Ready. Every tool kiyome needs is here."* ]]
}

@test "doctor reports a missing tool below the table" {
  # Arrange
  local farm
  farm="$(disk_test_farm openssl)"

  # Act
  run disk_test_run_path "${farm}" kiyome doctor </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"ERROR kiyome: a required tool is missing."* ]]
}

@test "doctor fails without gum" {
  # Arrange
  local farm
  farm="$(disk_test_farm gum)"

  # Act
  KIYOME_TEST_GUM=0 run disk_test_run_path "${farm}" kiyome doctor </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"gum                missing  install with: brew install gum"* ]]
}

@test "version shows the version and platform as badges" {
  # Arrange
  local version
  version="$(sed -n 's/^KIYOME_VERSION="\(.*\)"$/\1/p' "${REPO_DIR}/lib/core.sh")"

  # Act
  run disk_test_run kiyome version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "kiyome ${version} platform "* ]]
}

@test "help is formatted with gum" {
  # Arrange
  local expected="## Usage"

  # Act
  run disk_test_run kiyome help </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"${expected}"* ]]
  called "format --theme pink"
}

@test "--theme picks the palette over the environment" {
  # Arrange
  local theme="nord"

  # Act
  KODOUGU_THEME=dracula KIYOME_THEME=gruvbox run disk_test_run kiyome --theme "${theme}" version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #88C0D0"
}

@test "--theme= with a value picks the palette" {
  # Arrange
  local option="--theme=tokyo-night"

  # Act
  run disk_test_run kiyome "${option}" version </dev/null

  # Assert
  [[ "${status}" -eq 0 ]]
  called "--background #7AA2F7"
}

@test "an unknown theme stops before the disk is touched" {
  # Arrange
  local theme="solarized"

  # Act
  KODOUGU_THEME="${theme}" run disk_test_run kiyome "${DEVICE}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"got: solarized"* ]]
  untouched
}

@test "--theme without a value stops with the usage hint" {
  # Arrange
  local option="--theme"

  # Act
  run disk_test_run kiyome version "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"option '--theme' needs a value. run 'kiyome help' for usage."* ]]
}

@test "--theme after -- names the disk" {
  # Arrange
  local option="--theme"

  # Act
  run disk_test_run kiyome -- "${option}" </dev/null

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"--theme"* ]]
}

@test "a message after a progress bar still running starts on its own line" {
  # Arrange
  local call='disk_progress Writing 512 1024 0; disk_info "Told macOS not to mount the volume."'

  # Act
  run disk_test_call eval "disk_ui_setup && ${call}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"%"*$'\n'"Told macOS not to mount the volume."* ]]
}
