#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
minimum=${1:-95}
coverage_dir="${root}/coverage"
runs_dir="${coverage_dir}/runs"
merged_dir="${coverage_dir}/merged"
kcov_bin=$(command -v kcov)
hashbang=$(printf '\043\041')

rm -rf "${coverage_dir}"
mkdir -p "${runs_dir}"

wrapper="${coverage_dir}/kcov-shell"
{
  printf '%s/bin/sh\n' "${hashbang}"
  printf 'exec %s --bash-handle-sh-invocation --include-path=%s/bin,%s/lib "%s/run-$$" "$@"\n' \
    "${kcov_bin}" "${root}" "${root}" "${runs_dir}"
} >"${wrapper}"
chmod 0755 "${wrapper}"

DISK_COVERAGE=1 DISK_SHELL="${wrapper}" bats "${root}/test"

"${kcov_bin}" --merge "${merged_dir}" "${runs_dir}"/run-* >/dev/null 2>&1

summary=$(find "${merged_dir}" -name 'coverage.json' -print | head -n 1)
if [ -z "${summary}" ]; then
  printf 'no coverage.json produced under %s\n' "${merged_dir}" >&2
  exit 1
fi

python3 - "${summary}" "${minimum}" <<'PY'
import json
import sys

report = json.load(open(sys.argv[1]))
actual = float(report["percent_covered"])
minimum = float(sys.argv[2])
print("covered %s of %s lines (%.2f%%), gate %.2f%%" % (
    report["covered_lines"], report["total_lines"], actual, minimum))
if actual + 1e-9 < minimum:
    sys.stderr.write("coverage %.2f%% is below the %.2f%% gate\n" % (actual, minimum))
    sys.exit(1)
PY
