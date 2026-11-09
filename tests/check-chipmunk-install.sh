#!/usr/bin/env bash
set -euo pipefail

script="recipes/module-recipes/chipmunk.yml"
recipe="recipes/recipe.yml"

fail() {
  echo "check-chipmunk-install: $*" >&2
  exit 1
}

[[ -f "${script}" ]] || fail "missing ${script}"

grep -Fq "# Install Chipmunk (pinned v4.4.0, 2026-09-30)" "${script}" || fail "missing version/date annotation"
grep -Fq "CHIPMUNK_URL=\"https://github.com/esrlabs/chipmunk/releases/download/4.4.0/chipmunk@4.4.0-linux-x86_64.rpm\"" "${script}" || fail "missing pinned RPM URL"
grep -Fq 'dnf5 install -y "${CHIPMUNK_URL}"' "${script}" || fail "missing dnf5 install of the pinned RPM"

code="$(awk '{ sub(/^[[:space:]]+/, ""); if ($0 == "" || $0 ~ /^#/) next; print }' "${script}")"
code_last="$(printf '%s\n' "${code}" | awk 'NF { last = $0 } END { print last }')"
[[ "${code_last}" == "dnf5 clean all" ]] || fail "dnf5 clean all must be the last executable line"

chip_line="$(awk '/module-recipes\/chipmunk.yml/ { print NR }' "${recipe}")"
systemd_line="$(awk '/module-recipes\/systemd.yml/ { print NR }' "${recipe}")"
test -n "${chip_line}" && test -n "${systemd_line}" || fail "missing recipe module entry"
test "${chip_line}" -lt "${systemd_line}" || fail "chipmunk.yml must precede systemd.yml"

echo "check-chipmunk-install: OK"
