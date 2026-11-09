#!/usr/bin/env bash
set -euo pipefail

script="recipes/module-recipes/cc-switch.yml"
recipe="recipes/recipe.yml"

fail() {
  echo "check-cc-switch-install: $*" >&2
  exit 1
}

[[ -f "${script}" ]] || fail "missing ${script}"

grep -Fq "# Install CC Switch (pinned v4.0.9, 2026-10-11)" "${script}" || fail "missing version/date annotation"
grep -Fq "CC_SWITCH_URL=\"https://github.com/farion1231/cc-switch/releases/download/v4.0.9/CC-Switch-v4.0.9-Linux-x86_64.rpm\"" "${script}" || fail "missing pinned RPM URL"
grep -Fq 'dnf5 install -y "${CC_SWITCH_URL}"' "${script}" || fail "missing dnf5 install of the pinned RPM"

code="$(awk '{ sub(/^[[:space:]]+/, ""); if ($0 == "" || $0 ~ /^#/) next; print }' "${script}")"
code_last="$(printf '%s\n' "${code}" | awk 'NF { last = $0 } END { print last }')"
[[ "${code_last}" == "dnf5 clean all" ]] || fail "dnf5 clean all must be the last executable line"

cc_line="$(awk '/module-recipes\/cc-switch.yml/ { print NR }' "${recipe}")"
systemd_line="$(awk '/module-recipes\/systemd.yml/ { print NR }' "${recipe}")"
test -n "${cc_line}" && test -n "${systemd_line}" || fail "missing recipe module entry"
test "${cc_line}" -lt "${systemd_line}" || fail "cc-switch.yml must precede systemd.yml"

echo "check-cc-switch-install: OK"
