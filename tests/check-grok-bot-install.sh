#!/usr/bin/env bash
set -euo pipefail

script="recipes/module-recipes/scripts.yml"

fail() {
  echo "check-grok-bot-install: $*" >&2
  exit 1
}

# Comment-stripped, executable lines only: the block's comments name the vendor
# page, the yum repo, and the sandbox trade-off, so the negative assertions below
# must be checked against code, not prose.
code="$(awk '{ sub(/^[[:space:]]+/, ""); if ($0 == "" || $0 ~ /^#/) next; print }' "${script}")"

has_code() { grep -Fq -- "$1" <<< "${code}"; }

# --- positive: pinned vendor artifact, hash-verified --------------------------
grep -Fq "# Install Grok Bot (pinned" "${script}"
grep -Fq "GROK_BOT_RPM=\"/tmp/grok-bot.rpm\"" "${script}"
has_code 'GROK_BOT_URL="https://downloads.cursor.com/grokbot/stable/5acb0be5178da83005411731082da2dab1602ca7/linux/x64/grok-bot-0.75.3-1.x86_64.rpm"'
has_code 'GROK_BOT_SHA256="171c38d01377b7da2c3772c2cb1ad0f7fc749c2df4d2253052de9a02e2cfe9a8"'
has_code 'curl -fL "${GROK_BOT_URL}" -o "${GROK_BOT_RPM}"'
has_code 'printf '"'"'%s  %s\n'"'"' "${GROK_BOT_SHA256}" "${GROK_BOT_RPM}" | sha256sum -c -'
has_code 'Grok Bot RPM sha256 mismatch'

# The pinned filename names a version; the RPM header must agree. A renamed or
# retargeted artifact fails before anything is installed.
has_code "test \"\$(rpm -qp --qf '%{NAME}' \"\${GROK_BOT_RPM}\")\" = \"grok-bot\""
has_code "test \"\$(rpm -qp --qf '%{ARCH}' \"\${GROK_BOT_RPM}\")\" = \"x86_64\""
has_code "test \"\$(rpm -qp --qf '%{VERSION}-%{RELEASE}' \"\${GROK_BOT_RPM}\")\" = \"0.75.3-1\""
has_code 'dnf5 install -y "${GROK_BOT_RPM}"'
has_code 'rm -f "${GROK_BOT_RPM}"'

# Verification must precede installation, so a drifted CDN object cannot be
# installed first and checked afterwards.
sha_line="$(grep -n 'GROK_BOT_SHA256}" "${GROK_BOT_RPM}" | sha256sum -c -' "${script}" | cut -d: -f1)"
install_line="$(grep -n 'dnf5 install -y "${GROK_BOT_RPM}"' "${script}" | cut -d: -f1)"
test -n "${sha_line}" && test -n "${install_line}"
test "${sha_line}" -lt "${install_line}" || fail "sha256 verification must precede dnf5 install"

# The pinned URL may only ever point at the vendor CDN.
has_code 'case "${GROK_BOT_URL}" in'
has_code 'https://downloads.cursor.com/*) ;;'
has_code 'unexpected Grok Bot RPM host: ${GROK_BOT_URL}'

# --- positive: vendor %post repo is disabled, not enabled --------------------
# /usr is immutable on this image, so the repo the RPM registers cannot serve an
# in-place update; leaving it enabled would only widen dnf's third-party surface.
has_code "sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/grok-bot.repo"
has_code "test \"\$(sed -n 's/^enabled=//p' /etc/yum.repos.d/grok-bot.repo)\" = \"0\""

# --- positive: installed paths from the packaged layout ----------------------
has_code 'test -x /usr/bin/grok-bot'
has_code 'test -f /usr/share/applications/grok-bot.desktop'

# --- positive: placement and the single shared cleanup ----------------------
test "$(grep -c 'dnf5 clean all' "${script}")" -eq 1 || fail "dnf5 clean all must occur exactly once"
code_last="$(printf '%s\n' "${code}" | awk 'NF { last = $0 } END { print last }')"
[[ "${code_last}" == "dnf5 clean all" ]] || fail "dnf5 clean all must be the last executable line of the snippet"

# Grouped with the pinned vendor URLs: after Chipmunk, before Proton Pass.
chip_line="$(grep -n '# Install Chipmunk (pinned' "${script}" | cut -d: -f1)"
grok_line="$(grep -n '# Install Grok Bot (pinned' "${script}" | cut -d: -f1)"
pass_line="$(grep -n "# Install Proton Pass Desktop" "${script}" | cut -d: -f1)"
test -n "${chip_line}" && test -n "${grok_line}" && test -n "${pass_line}"
test "${chip_line}" -lt "${grok_line}" || fail "Grok Bot must follow the Chipmunk block"
test "${grok_line}" -lt "${pass_line}" || fail "Grok Bot must precede the Proton Pass block"

# --- negative: no scraping, no sandbox override, no foreign packaging --------
if printf '%s\n' "${code}" | grep -Fq 'x.ai/bot'; then
  fail "the build must not scrape x.ai/bot; the artifact URL is pinned"
fi

# The vendor yum repo is documented in comments as a lagging alternative; the
# block itself must not add or enable it.
if printf '%s\n' "${code}" | grep -Fq 'yumrepo/grok-bot'; then
  fail "the signed yum repo is recorded in comments, not enabled in the block"
fi

# chrome-sandbox mode is the vendor %post decision (4755 or 0755, depending on
# host user namespaces); the block must neither chmod it nor disable it.
if printf '%s\n' "${code}" | grep -Eq 'chmod[^#]*chrome-sandbox'; then
  fail "chrome-sandbox mode belongs to the vendor scriptlet, not this block"
fi
if printf '%s\n' "${code}" | grep -Fq -- '--no-sandbox'; then
  fail "no --no-sandbox flag may be added anywhere"
fi

if printf '%s\n' "${code}" | grep -Eqi '(flatpak|snap)[[:space:]]+(install|add|run)'; then
  fail "Grok Bot must come from the vendor RPM, not flatpak/snap"
fi

# Nothing here asserts the absence of other vendors' literals: scripts.yml is
# shared, and a whole-file negative would break when a sibling block lands.

echo "check-grok-bot-install: OK"
