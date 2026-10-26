#!/bin/sh

# shellcheck source=SCRIPTDIR/state.sh
. "${DISK_LIB:?}/state.sh"

disk_whole_of() {
  disk_wo_os="$(disk_os)"
  case "${disk_wo_os}" in
    Darwin)
      disk_wo_whole="$(disk_plist_value "$1" ParentWholeDisk)"
      [ -n "${disk_wo_whole}" ] || return 0
      printf '/dev/%s\n' "${disk_wo_whole}"
      disk_wo_store="$(disk_plist_value "${disk_wo_whole}" APFSPhysicalStores.0.APFSPhysicalStore)"
      if [ -n "${disk_wo_store}" ]; then
        disk_wo_parent="$(disk_plist_value "${disk_wo_store}" ParentWholeDisk)"
        [ -n "${disk_wo_parent}" ] && printf '/dev/%s\n' "${disk_wo_parent}"
      fi
      ;;
    Linux)
      disk_wo_tree="$(lsblk -nrso NAME,TYPE "$1" 2>/dev/null)"
      printf '%s\n' "${disk_wo_tree}" | awk '$2 == "disk" || $2 == "loop" { print "/dev/" $1 }'
      ;;
    *) ;;
  esac
  return 0
}

disk_boot_disks() {
  disk_bd_os="$(disk_os)"
  if [ "${disk_bd_os}" = "Darwin" ]; then
    disk_whole_of /
    disk_whole_of /System/Volumes/Data
  else
    disk_bd_root="$(findmnt -n -o SOURCE / 2>/dev/null)"
    [ -n "${disk_bd_root}" ] && disk_whole_of "${disk_bd_root}"
  fi
  return 0
}

disk_listed() {
  printf '%s\n' "$2" | grep -qx -- "$1"
}

disk_is_internal() {
  disk_ii_os="$(disk_os)"
  case "${disk_ii_os}" in
    Darwin)
      disk_ii_internal="$(disk_plist_value "$1" Internal)"
      disk_ii_eject="$(disk_plist_value "$1" Ejectable)"
      [ "${disk_ii_internal}" = "true" ] && [ "${disk_ii_eject}" != "true" ]
      ;;
    Linux)
      disk_ii_flags="$(lsblk -dnro RM,HOTPLUG,TRAN "$1" 2>/dev/null)"
      case "${disk_ii_flags}" in
        1\ * | ?\ 1* | *usb* | *mmc*) return 1 ;;
        *) return 0 ;;
      esac
      ;;
    *) return 0 ;;
  esac
}

disk_human() {
  awk -v b="$1" 'BEGIN {
    split("B KiB MiB GiB TiB", u, " ")
    i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf (i == 1 ? "%d %s\n" : "%.1f %s\n"), b, u[i]
  }'
}

disk_candidates() {
  disk_cn_os="$(disk_os)"
  case "${disk_cn_os}" in
    Darwin)
      disk_cn_list="$(diskutil list 2>/dev/null)"
      printf '%s\n' "${disk_cn_list}" | awk '/^\/dev\/disk[0-9]+ / && !/synthesized/ { print $1 }'
      ;;
    Linux)
      disk_cn_list="$(lsblk -dnro NAME,TYPE,SIZE -b 2>/dev/null)"
      printf '%s\n' "${disk_cn_list}" | awk '($2 == "disk" || $2 == "loop") && $3 > 0 { print "/dev/" $1 }'
      ;;
    *) ;;
  esac
  return 0
}

disk_eligible() {
  disk_el_boot="$(disk_boot_disks)"
  disk_el_all="$(disk_candidates)"
  for disk_el_disk in ${disk_el_all}; do
    disk_listed "${disk_el_disk}" "${disk_el_boot}" && continue
    if [ "${ALLOW_INTERNAL:-}" != "y" ] && disk_is_internal "${disk_el_disk}"; then
      continue
    fi
    printf '%s\n' "${disk_el_disk}"
  done
  return 0
}

disk_pick_targets() {
  disk_pt_list="$(disk_eligible)"
  if [ -z "${disk_pt_list}" ]; then
    disk_error "No external or removable disk is attached." >&2
    return 1
  fi
  disk_pt_index=0
  for disk_pt_disk in ${disk_pt_list}; do
    disk_pt_index=$((disk_pt_index + 1))
    disk_pt_size="$(disk_size_bytes "${disk_pt_disk}")"
    disk_is_uint "${disk_pt_size}" || disk_pt_size=0
    disk_pt_human="$(disk_human "${disk_pt_size}")"
    disk_pt_id="$(disk_identity "${disk_pt_disk}")"
    printf '  %d) %-14s %10s  %s\n' "${disk_pt_index}" "${disk_pt_disk}" "${disk_pt_human}" "${disk_pt_id}" >&2
  done
  printf '%s' "${DISK_PICK_PROMPT:-Write to which disk(s)? Numbers or names, separated by commas: }" >&2
  disk_pt_answer=""
  IFS= read -r disk_pt_answer
  disk_pt_answer="$(printf '%s' "${disk_pt_answer}" | tr -s ', ' '\n')"
  for disk_pt_choice in ${disk_pt_answer}; do
    disk_pick_one "${disk_pt_choice}" "${disk_pt_list}" "${disk_pt_index}" || return 1
  done
  return 0
}

disk_pick_one() {
  if disk_is_uint "$1" && [ "$1" -ge 1 ] && [ "$1" -le "$3" ]; then
    printf '%s\n' "$2" | sed -n "$1p"
    return 0
  fi
  for disk_po_disk in $2; do
    if [ "${disk_po_disk}" = "$1" ] || [ "${disk_po_disk##*/}" = "$1" ]; then
      printf '%s\n' "${disk_po_disk}"
      return 0
    fi
  done
  disk_error "Not a listed number or disk: $1"
  return 1
}


disk_refuse_target() {
  disk_rt_boot="$(disk_boot_disks)"
  if disk_listed "$1" "${disk_rt_boot}"; then
    disk_error "STOPPED: $1 holds the running system, so it is never wiped."
    return 1
  fi
  if [ "${ALLOW_INTERNAL:-}" != "y" ] && disk_is_internal "$1"; then
    disk_error "STOPPED: $1 is an internal disk. Set ALLOW_INTERNAL=y to wipe it on purpose."
    return 1
  fi
  return 0
}
