#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_cli_hint() {
  printf "%s: %s. run '%s help' for usage.\n" "${DISK_PROG}" "$1" "${DISK_PROG}" >&2
}

disk_cli_version() {
  disk_version "${DISK_PROG}"
  disk_cv_platform="$(uname -sr)" || disk_cv_platform="unknown"
  printf 'platform: %s\n' "${disk_cv_platform}"
}

disk_doctor_row() {
  printf '%-18s %-8s %s\n' "$1" "$2" "$3"
}

disk_doctor_tool() {
  disk_dt_found="$(command -v "$1" 2>/dev/null || true)"
  if [ -n "${disk_dt_found}" ]; then
    disk_doctor_row "$1" ok "${disk_dt_found}"
    return 0
  fi
  disk_doctor_row "$1" missing "$3"
  [ "$2" = required ] && return 1
  return 0
}

disk_doctor_either() {
  if command -v "$1" >/dev/null 2>&1 || command -v "$2" >/dev/null 2>&1; then
    disk_de_found="$(command -v "$1" 2>/dev/null || command -v "$2")"
    disk_doctor_row "$1|$2" ok "${disk_de_found}"
    return 0
  fi
  disk_doctor_row "$1|$2" missing "$4"
  [ "$3" = required ] && return 1
  return 0
}

disk_doctor_platform() {
  disk_dp_status=0
  case "$(uname -s)" in
  Darwin)
    disk_doctor_tool diskutil required "lists and ejects disks" || disk_dp_status=1
    disk_doctor_tool hdiutil required "reads volume UUIDs without mounting" || disk_dp_status=1
    ;;
  *)
    disk_doctor_tool lsblk required "lists disks" || disk_dp_status=1
    disk_doctor_tool blockdev required "reads disk sizes" || disk_dp_status=1
    disk_doctor_tool udevadm required "keeps udisks from mounting the target" || disk_dp_status=1
    ;;
  esac
  return "${disk_dp_status}"
}

disk_doctor_core() {
  disk_dc_status=0
  for disk_dc_tool in dd cmp od awk sed sudo; do
    disk_doctor_tool "${disk_dc_tool}" required "required" || disk_dc_status=1
  done
  disk_doctor_either sha256sum shasum required "validates the written disk" || disk_dc_status=1
  disk_doctor_platform || disk_dc_status=1
  return "${disk_dc_status}"
}

disk_doctor_formats() {
  disk_doctor_tool curl optional "needed to write from a URL"
  disk_doctor_tool gzip optional "needed for .gz images"
  disk_doctor_tool xz optional "needed for .xz images"
  disk_doctor_tool zstd optional "needed for .zst images"
  disk_doctor_tool bzip2 optional "needed for .bz2 images"
  disk_doctor_either bsdtar 7z optional "needed for .zip images and Windows ISOs"
  disk_doctor_tool qemu-img optional "needed for .vhd, .vhdx, .vmdk and .qcow2 images"
  disk_doctor_tool mcopy optional "mtools, needed for Windows ISOs and format"
  disk_doctor_tool wimlib-imagex optional "wimlib, needed for Windows ISOs over 4 GiB"
}

disk_doctor() {
  disk_dr_status=0
  disk_doctor_core || disk_dr_status=1
  case "${DISK_PROG}" in
  kiyome) disk_doctor_tool openssl required "builds the per-chunk unique pattern" || disk_dr_status=1 ;;
  *) disk_doctor_formats ;;
  esac
  return "${disk_dr_status}"
}

disk_cli_interactive() {
  [ "${DISK_INTERACTIVE:-}" = 1 ] && return 0
  [ -t 0 ]
}

disk_prompt() {
  if [ -n "$2" ]; then
    printf '%s [%s]: ' "$1" "$2" >&2
  else
    printf '%s: ' "$1" >&2
  fi
  disk_ak_answer=""
  IFS= read -r disk_ak_answer || [ -n "${disk_ak_answer}" ] || return 1
  printf '%s\n' "${disk_ak_answer:-$2}"
}

disk_ask_required() {
  disk_ar_tries=0
  while [ "${disk_ar_tries}" -lt 3 ]; do
    disk_ar_value="$(disk_prompt "$1" "")" || return 1
    if [ -n "${disk_ar_value}" ]; then
      printf '%s\n' "${disk_ar_value}"
      return 0
    fi
    disk_ar_tries=$((disk_ar_tries + 1))
  done
  disk_cli_hint "$2"
  return 1
}

disk_pick_single() {
  disk_ps_list="$(DISK_PICK_PROMPT="$1" disk_pick_targets)" || return 1
  disk_ps_count="$(printf '%s\n' "${disk_ps_list}" | awk 'NF' | wc -l | tr -d '[:space:]')"
  if [ "${disk_ps_count}" -ne 1 ]; then
    disk_error "Pick exactly one disk."
    return 1
  fi
  printf '%s\n' "${disk_ps_list}"
}
