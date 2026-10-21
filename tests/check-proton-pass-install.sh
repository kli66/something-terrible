#!/usr/bin/env bash
set -euo pipefail

script="recipes/module-recipes/scripts.yml"
recipe="recipes/recipe.yml"

fail() {
  echo "check-proton-pass-install: $*" >&2
  exit 1
}

# Comment-stripped, executable lines only. The block's comments explain what it
# deliberately does NOT do (no setuid bit, no --no-sandbox, no vendor install.sh),
# so the negative assertions below must be checked against code, not comment prose.
code="$(awk '{ sub(/^[[:space:]]+/, ""); if ($0 == "" || $0 ~ /^#/) next; print }' "${script}")"

# Anything that has to actually run is asserted against "${code}", so commenting
# out the trust boundary (or a guard) fails here instead of passing on prose.
has_code() { grep -Fq -- "$1" <<< "${code}"; }

# --- positive: the vendor-manifest + checksum-verified install pattern ---------
grep -Fq "# Install Proton Pass Desktop + CLI from Proton's official channel." "${script}"
has_code 'PASS_GUI_MANIFEST_URL="https://proton.me/download/PassDesktop/linux/x64/version.json"'
has_code 'PASS_CLI_MANIFEST_URL="https://proton.me/download/pass-cli/versions.json"'
has_code 'select(.CategoryName == "Stable")'
has_code 'sort_by(.ReleaseDate)'
has_code '.rpm (Fedora/RHEL)'
has_code 'sha512sum -c -'
has_code 'sha256sum -c -'
has_code 'command -v jq >/dev/null || dnf5 install -y jq'
has_code 'dnf5 install -y "${PASS_RPM}"'
has_code 'install -Dm0755 "${PASS_CLI_BIN}" /usr/bin/pass-cli'
has_code 'rpm -q proton-pass'
has_code 'pass-cli --version'

# Design constraint 11: assertions compare against the manifest-derived version.
has_code 'test "$(rpm -q --qf'
has_code '"${PASS_VERSION}-1"'

# formatVersion is the vendor install.sh's own guard; mirroring it fails closed.
has_code "test \"\$(jq -er '.formatVersion' \"\${PASS_CLI_MANIFEST}\")\" = \"1\""

# Both resolved URLs must be gated on the Proton host, so an off-host manifest
# stops the build instead of fetching whatever it names.
has_code 'case "${PASS_RPM_URL}" in'
has_code 'case "${PASS_CLI_URL}" in'
has_code 'https://proton.me/*) ;;'

# The vendor artifact's security posture is asserted, not modified.
has_code "test \"\$(stat -c '%a' /usr/lib/proton-pass/chrome-sandbox)\" = \"755\""
has_code 'test ! -u /usr/lib/proton-pass/chrome-sandbox'
# The rest of the post-install assertion block the ticket requires. These are
# asserted as executable lines for the same reason as the block above: an
# assertion that has been commented out must fail here, not pass on prose.
has_code 'test -x /usr/bin/proton-pass'
has_code 'test "$(readlink -f /usr/bin/proton-pass)" = "/usr/lib/proton-pass/Proton Pass"'
has_code 'test -f /usr/share/applications/proton-pass.desktop'
has_code 'test ! -e /etc/yum.repos.d/proton.repo'
has_code 'test -z "${PASS_HOME_STATE}"'
has_code 'PASS_HOME_STATE="$(find "${HOME}"'
has_code '= "proton-pass"'
has_code '= "x86_64"'
has_code '"7f454c46"'

# The trust boundary must fail loudly, not merely lean on errexit: both hash
# checks carry an explicit failure branch, so assert the branch text too.
has_code 'Proton Pass RPM sha512 mismatch'
has_code 'pass-cli sha256 mismatch'

# --- positive: one snippet, one cleanup, unchanged module order ---------------
test "$(grep -c 'dnf5 clean all' "${script}")" -eq 1 || fail "dnf5 clean all must occur exactly once"
# Checked against the comment-stripped stream so that a commented-out
# "# dnf5 clean all" tail cannot satisfy it, and so the assertion does not pin
# the YAML block-scalar indentation.
code_last="$(printf '%s\n' "${code}" | awk 'NF { last = $0 } END { print last }')"
[[ "${code_last}" == "dnf5 clean all" ]] || fail "dnf5 clean all must be the last executable line of the snippet"

scripts_line="$(awk '/module-recipes\/scripts.yml/ { print NR }' "${recipe}")"
systemd_line="$(awk '/module-recipes\/systemd.yml/ { print NR }' "${recipe}")"
test "${scripts_line}" -lt "${systemd_line}"

# --- positive: the earlier vendored blocks are untouched ----------------------
# These headers are comments, so they are file-scoped by nature.
grep -Fq "# Install Bettbox (pinned" "${script}"
grep -Fq "# Install CC Switch (pinned" "${script}"
grep -Fq "# Install Chipmunk (pinned" "${script}"
grep -Fq "# Install Bitwarden Desktop (vendor redirects" "${script}"
has_code 'terra-bootstrap'
has_code "sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/terra*.repo"

# --- negative: official Proton channel only ----------------------------------
if printf '%s\n' "${code}" | grep -Eqi '(flatpak|snap)[[:space:]]+(install|add|run)'; then
  fail "Proton Pass must come from Proton's channel, not flatpak/snap"
fi

# The vendor install.sh is read as documentation, never executed; no remote
# script is piped into a shell.
if printf '%s\n' "${code}" | grep -Eq 'install\.sh|\|[[:space:]]*(ba|da|z)?sh([[:space:]]|$)'; then
  fail "no vendor install.sh execution and no curl-into-shell"
fi

# /usr/local is a symlink to /var/usrlocal on this image, so the only permitted
# mention of the vendor default path is the assertion that it is absent.
while IFS= read -r line; do
  [[ "${line}" == *"/usr/local/bin/pass-cli"* ]] || continue
  [[ "${line}" == "test ! -e /usr/local/bin/pass-cli" ]] || fail "pass-cli must be installed to /usr/bin, not /usr/local/bin: ${line}"
done <<< "${code}"

# Path-scoped on purpose: the Bettbox block legitimately sets its own u+s bit,
# so a bare setuid grep would fail today.
if printf '%s\n' "${code}" | grep -Eq 'chmod[^#]*/usr/lib/proton-pass/chrome-sandbox'; then
  fail "chrome-sandbox must keep the shipped 0755 mode, without a setuid bit"
fi
if printf '%s\n' "${code}" | grep -Fq -- '--no-sandbox'; then
  fail "no --no-sandbox flag may be added anywhere"
fi

# No vendor URL in this block may sit off-host: a literal manifest URL has to be
# proton.me, and a URL computed from the manifest is host-guarded by the case
# assertions above.
while IFS= read -r line; do
  case "${line}" in
    PASS_*URL=\"https://*)
      [[ "${line}" == PASS_*'"https://proton.me/'* ]] || fail "off-host vendor URL: ${line}"
      ;;
  esac
done <<< "${code}"

# Design constraint 11: every asserted version is manifest-derived. The pinned
# Bettbox / CC Switch / Chipmunk URL constants legitimately carry version
# literals (1.19.4, 4.0.9, 4.4.0), so this negative is scoped to the Proton Pass
# block instead of the whole file.
pass_block="$(awk '/^PASS_GUI_MANIFEST_URL=/ { inblock = 1 } inblock && /^dnf5 clean all$/ { inblock = 0 } inblock { print }' <<< "${code}")"
test -n "${pass_block}" || fail "could not locate the Proton Pass block in scripts.yml"
if grep -Eq '[0-9]+\.[0-9]+\.[0-9]+' <<< "${pass_block}"; then
  fail "Proton Pass assertions must use the manifest-derived version, not a hardcoded literal"
fi

# --- negative: no baked account, session, token, or keyring state ------------
if printf '%s\n' "${code}" | grep -Eqi 'pass-cli[[:space:]]+(login|logout|create|api-token)|--token'; then
  fail "the build must not authenticate against Proton"
fi
if grep -Fq '.config/proton-pass' "${script}" || grep -Fq '.local/share/proton-pass' "${script}"; then
  fail "per-user Proton Pass state must not be baked into the image"
fi
if find files/system -iname '*proton*' -print -quit | grep -q .; then
  fail "no Proton Pass config, session, or native-messaging host may be baked under files/system"
fi

# Deliberately no whole-file negative on 1Password literals: scripts.yml is
# shared with the additive add-1password block, so such an assertion would fail
# the moment that sibling change lands.

echo "check-proton-pass-install: OK"
