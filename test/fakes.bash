#!/usr/bin/env bash

fake_dir() {
  printf '%s/fake\n' "${WORK:?}"
}

fake_install() {
  local fake
  fake="$(fake_dir)"
  mkdir -p "${fake}/plist"
  case "$(uname -s)" in
  Darwin) fake_install_darwin "${fake}" ;;
  Linux) fake_install_linux "${fake}" ;;
  *) return 1 ;;
  esac
}

fake_install_darwin() {
  local fake="$1"
  disk_test_shim diskutil "fake='${fake}'
if [ \"\$1\" = info ] && [ -e \"\$fake/gone\" ]; then
  exit 1
fi
case \"\$1 \${2:-}\" in
  'info -plist')
    \"\$REAL\" \"\$@\" | awk -v dir=\"\$fake/plist\" '
      swap != \"\" { while ((getline line < (dir \"/\" swap)) > 0) print line; close(dir \"/\" swap); swap = \"\"; next }
      match(\$0, /<key>[A-Za-z]+<\\/key>/) { key = substr(\$0, RSTART + 5, RLENGTH - 11); if ((getline probe < (dir \"/\" key)) > 0) { swap = key }; close(dir \"/\" key) }
      { print }'
    exit 0
    ;;
  info\\ /*)
    if [ -f \"\$fake/info.sed\" ]; then
      \"\$REAL\" \"\$@\" | sed -f \"\$fake/info.sed\"
      exit 0
    fi
    ;;
  'eject '*) [ -e \"\$fake/eject-fails\" ] && exit 1 ;;
  'unmountDisk '*) [ -e \"\$fake/unmount-fails\" ] && exit 1 ;;
esac
exec \"\$REAL\" \"\$@\""
  disk_test_shim mount "\"\$REAL\" \"\$@\"
fake='${fake}'
if [ -f \"\$fake/mounts\" ] && { [ ! -e \"\$fake/mounts-after\" ] || [ -e \"\$fake/wiped\" ]; }; then
  cat \"\$fake/mounts\"
fi"
}

fake_install_linux() {
  local fake="$1"
  disk_test_shim lsblk "fake='${fake}'
case \"\$*\" in
  *VENDOR*) [ -f \"\$fake/model\" ] && { printf 'IOMEGA\\n'; exit 0; } ;;
  *MODEL*) [ -f \"\$fake/model\" ] && { cat \"\$fake/model\"; exit 0; } ;;
  *MOUNTPOINT*)
    [ -e \"\$fake/mount-state-fails\" ] && exit 1
    [ -f \"\$fake/mounts\" ] && { cat \"\$fake/mounts\"; exit 0; }
    ;;
esac
exec \"\$REAL\" \"\$@\""
  disk_test_shim blockdev "fake='${fake}'
case \"\$*\" in
  *--getro*) [ -f \"\$fake/readonly\" ] && { printf '1\\n'; exit 0; } ;;
  *--getsize64*)
    [ -e \"\$fake/size-fails\" ] && exit 1
    [ -e \"\$fake/gone\" ] && exit 1
    [ -f \"\$fake/size\" ] && { cat \"\$fake/size\"; exit 0; }
    ;;
esac
exec \"\$REAL\" \"\$@\""
  disk_test_shim eject "[ -e '${fake}/eject-fails' ] && exit 1
exec \"\$REAL\" \"\$@\""
}

fake_identity_as() {
  local model="$1"
  local fake
  fake="$(fake_dir)"
  printf '%s\n' "${model}" >"${fake}/model"
  printf '<string>%s</string>\n' "${model}" >"${fake}/plist/MediaName"
}

fake_read_only() {
  local fake
  fake="$(fake_dir)"
  : >"${fake}/readonly"
  printf '<false/>\n' >"${fake}/plist/WritableMedia"
}

fake_size_bytes() {
  local bytes="$1"
  local fake
  fake="$(fake_dir)"
  printf '%s\n' "${bytes}" >"${fake}/size"
  printf 's/([0-9][0-9]* Bytes)/(%s Bytes)/\n' "${bytes}" >"${fake}/info.sed"
}

fake_size_unknown() {
  local fake
  fake="$(fake_dir)"
  : >"${fake}/size-fails"
  printf '/Disk Size:/d\n' >"${fake}/info.sed"
}

fake_flag() {
  : >"$(fake_dir)/$1"
}
