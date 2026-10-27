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

disk_flavor_version() {
  printf '%s\n' "$1" | awk '{
    for (i = 1; i <= NF; i++) {
      t = $i
      gsub(/[,;()]/, "", t)
      sub(/^v/, "", t)
      if (t ~ /^[0-9]+(\.[0-9]+)+[a-z0-9]*$/ || t ~ /^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]$/) { print t; exit }
    }
  }'
}

disk_tool_flavor() {
  disk_tf_raw="$("$1" --version 2>&1 </dev/null)" || true
  disk_tf_text="$(printf '%s\n' "${disk_tf_raw}" | sed -n '1p')"
  disk_tf_version="$(disk_flavor_version "${disk_tf_text}")"
  disk_tf_os="$(disk_os)"
  case "${disk_tf_text}" in
    *uutils*) disk_tf_name=uutils ;;
    *BusyBox*) disk_tf_name=busybox ;;
    *GNU* | *GLIBC* | *"(coreutils)"* | *"(diffutils)"*) disk_tf_name=gnu ;;
    *mawk*) disk_tf_name=mawk ;;
    *"awk version"* | *"(Darwin)"*) disk_tf_name=bsd ;;
    *)
      disk_tf_version=""
      case "$1:${disk_tf_os}" in
        *uutils*:* | */cargo/*:*) disk_tf_name=uutils ;;
        *:Darwin | *:*BSD) disk_tf_name=bsd ;;
        *) disk_tf_name=unknown ;;
      esac
      ;;
  esac
  printf '%s%s\n' "${disk_tf_name}" "${disk_tf_version:+ ${disk_tf_version}}"
}

disk_doctor_note() {
  case "${1##*/}" in
    dd | cmp | od | awk | sed | sha256sum) disk_tool_flavor "$1" ;;
    shasum)
      disk_dn_raw="$("$1" --version 2>&1 </dev/null)" || true
      disk_dn_version="$(disk_flavor_version "${disk_dn_raw}")"
      printf 'perl%s\n' "${disk_dn_version:+ ${disk_dn_version}}"
      ;;
    *) ;;
  esac
}

disk_doctor_found() {
  disk_df_note="$(disk_doctor_note "$1")"
  printf '%s%s\n' "$1" "${disk_df_note:+, ${disk_df_note}}"
}

disk_doctor_tool() {
  disk_dt_found="$(command -v "$1" 2>/dev/null || true)"
  if [ -n "${disk_dt_found}" ]; then
    disk_dt_detail="$(disk_doctor_found "${disk_dt_found}")"
    disk_doctor_row "$1" ok "${disk_dt_detail}"
    return 0
  fi
  disk_doctor_row "$1" missing "$2"
  return 1
}

disk_doctor_either() {
  if command -v "$1" >/dev/null 2>&1 || command -v "$2" >/dev/null 2>&1; then
    disk_de_found="$(command -v "$1" 2>/dev/null || command -v "$2")"
    disk_de_detail="$(disk_doctor_found "${disk_de_found}")"
    disk_doctor_row "$1|$2" ok "${disk_de_detail}"
    return 0
  fi
  disk_doctor_row "$1|$2" missing "$3"
  return 1
}

disk_doctor_platform() {
  disk_dp_status=0
  case "$(uname -s)" in
  Darwin)
    disk_doctor_tool diskutil "lists and ejects disks" || disk_dp_status=1
    disk_doctor_tool hdiutil "reads volume UUIDs without mounting" || disk_dp_status=1
    ;;
  *)
    disk_doctor_tool lsblk "lists disks" || disk_dp_status=1
    disk_doctor_tool blockdev "reads disk sizes" || disk_dp_status=1
    disk_doctor_tool udevadm "keeps udisks from mounting the target" || disk_dp_status=1
    ;;
  esac
  return "${disk_dp_status}"
}

disk_doctor_core() {
  disk_dc_status=0
  for disk_dc_tool in dd cmp od awk sed sudo; do
    disk_doctor_tool "${disk_dc_tool}" "required" || disk_dc_status=1
  done
  disk_doctor_either sha256sum shasum "validates the written disk" || disk_dc_status=1
  disk_doctor_platform || disk_dc_status=1
  return "${disk_dc_status}"
}

disk_doctor() {
  disk_dr_status=0
  disk_doctor_core || disk_dr_status=1
  disk_doctor_tool openssl "builds the per-chunk unique pattern" || disk_dr_status=1
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

disk_pick_single() {
  disk_ps_list="$(DISK_PICK_PROMPT="$1" disk_pick_targets)" || return 1
  disk_ps_count="$(printf '%s\n' "${disk_ps_list}" | awk 'NF' | wc -l | tr -d '[:space:]')"
  if [ "${disk_ps_count}" -ne 1 ]; then
    disk_error "pick exactly one disk."
    return 1
  fi
  printf '%s\n' "${disk_ps_list}"
}

disk_cli_is_option() {
  case "$1" in
    --* | -?*) return 0 ;;
    *) return 1 ;;
  esac
}

disk_cli_takes_value() {
  case " ${DISK_VALUE_OPTIONS} " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

disk_cli_assign() {
  if ! disk_cli_takes_value "${1%%=*}"; then
    if disk_option_flag "${1%%=*}"; then
      disk_cli_hint "option '${1%%=*}' takes no value"
    else
      disk_cli_hint "unknown option '${1%%=*}'"
    fi
    return 1
  fi
  disk_option_value "${1%%=*}" "${1#*=}"
}

disk_cli_option() {
  DISK_CLI_USED=0
  case "$1" in
    --*=*) disk_cli_assign "$1" ;;
    --?*)
      disk_option_flag "$1" && return 0
      if ! disk_cli_takes_value "$1"; then
        disk_cli_hint "unknown option '$1'"
        return 1
      fi
      if [ "$2" -lt 1 ]; then
        disk_cli_hint "option '$1' needs a value"
        return 1
      fi
      DISK_CLI_USED=1
      disk_option_value "$1" "$3"
      ;;
    *)
      disk_cli_hint "unknown option '$1'"
      return 1
      ;;
  esac
}
