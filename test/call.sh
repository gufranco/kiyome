#!/bin/sh
[ -n "${ZSH_VERSION:-}" ] && emulate sh

DISK_LIB="$(cd "$(dirname "$0")/../lib" && pwd)" || exit 1

# shellcheck source=SCRIPTDIR/../lib/core.sh
. "${DISK_LIB}/core.sh"
# shellcheck source=SCRIPTDIR/../lib/io.sh
. "${DISK_LIB}/io.sh"
# shellcheck source=SCRIPTDIR/../lib/calibrate.sh
. "${DISK_LIB}/calibrate.sh"
# shellcheck source=SCRIPTDIR/../lib/wipe.sh
. "${DISK_LIB}/wipe.sh"
# shellcheck source=SCRIPTDIR/../lib/ui.sh
. "${DISK_LIB}/ui.sh"
# shellcheck source=SCRIPTDIR/../lib/boot.sh
. "${DISK_LIB}/boot.sh"
# shellcheck source=SCRIPTDIR/../lib/cli.sh
. "${DISK_LIB}/cli.sh"

call_pattern() {
  disk_make_tmpdir pattern || return 1
  disk_cp_file="$(disk_pattern_file "$1" "$2")" || return 1
  od -An -tx1 -v "${disk_cp_file}" | awk '{ for (i = 1; i <= NF; i++) seen[$i] = 1 } END { for (b in seen) printf "%s ", b }'
  wc -c <"${disk_cp_file}"
}

call_report_failure() {
  disk_set_error "$1"
  disk_report_failure "$2"
  disk_get_error
}

call_first_boot_disk() {
  disk_cb_list="$(disk_boot_disks)"
  printf '%s\n' "${disk_cb_list}" | sed -n '1p'
}

"$@"
