#!/usr/bin/env bash
set -euo pipefail

script="recipes/module-recipes/grok-bot.yml"
recipe="recipes/recipe.yml"

fail() {
  echo "check-grok-bot-install: $*" >&2
  exit 1
}

[[ -f "${script}" ]] || fail "missing ${script}"

# Comment-stripped, executable lines only: the module's comments name the retired
# download page, the old pin, and the sandbox trade-off, so the negative assertions
# below must be checked against code, not prose.
code="$(awk '{ sub(/^[[:space:]]+/, ""); if ($0 == "" || $0 ~ /^#/) next; print }' "${script}")"

has_code() { grep -Fq -- "$1" <<< "${code}"; }

# --- positive: signed vendor repo, pinned by key hash ------------------------
grep -Fq "# Install Grok Bot from the vendor's OpenPGP-signed yum repo" "${script}"
has_code 'GROK_BOT_KEY_URL="https://downloads.cursor.com/keys/anysphere.asc"'
has_code 'GROK_BOT_KEY_SHA256="9d2adcc95efdf65e6e76f964968734551ab70181634781f9d5952b271895ec03"'
has_code 'GROK_BOT_KEY_FPR="380ff4bcdc34a4bd92a3565342a1772e62e492d6"'

# The key is the trust root, so it is fetched, hashed, and only then used.
has_code 'curl -fL "${GROK_BOT_KEY_URL}" -o "${GROK_BOT_KEY_FILE}"'
has_code 'printf '"'"'%s  %s\n'"'"' "${GROK_BOT_KEY_SHA256}" "${GROK_BOT_KEY_FILE}" | sha256sum -c -'
has_code 'Grok Bot signing key sha256 mismatch'

# dnf is pointed at the verified file, and both signature layers stay on.
has_code 'baseurl=https://downloads.cursor.com/yumrepo/grok-bot'
has_code 'gpgcheck=1'
has_code 'repo_gpgcheck=1'
has_code 'gpgkey=file://${GROK_BOT_KEY_FILE}'

keyhash_line="$(grep -n 'GROK_BOT_KEY_SHA256}" "${GROK_BOT_KEY_FILE}" | sha256sum -c -' "${script}" | cut -d: -f1)"
repo_line="$(grep -n 'cat > "${GROK_BOT_REPO_FILE}"' "${script}" | cut -d: -f1)"
test -n "${keyhash_line}" && test -n "${repo_line}"
test "${keyhash_line}" -lt "${repo_line}" || fail "the key hash must be verified before dnf is pointed at it"

# --- positive: resolve, install, then assert against the resolved version ----
has_code 'dnf5 --assumeyes repoquery --repo grok-bot-vendor --available \'
has_code '--latest-limit 1 --qf '"'"'%{version}-%{release}'"'"' grok-bot 2>/dev/null | tail -n1)"'
has_code 'Grok Bot repo resolved no signed package'
has_code 'dnf5 install -y grok-bot'
has_code "test \"\$(rpm -q --qf '%{VERSION}-%{RELEASE}' grok-bot)\" = \"\${GROK_BOT_RESOLVED}\""
has_code 'installed grok-bot is not the version the repo resolved'
has_code "test \"\$(rpm -q --qf '%{ARCH}' grok-bot)\" = \"x86_64\""
has_code 'rpm -q gpg-pubkey | grep -qF "${GROK_BOT_KEY_FPR}"'
has_code 'unexpected Grok Bot signing key in the rpmdb'

# No second version literal: the assertion compares against what this build's repo
# offered, so a bump needs no edit here.
if printf '%s\n' "${code}" | grep -Eq 'grok-bot-0\.[0-9]+\.[0-9]+'; then
  fail "a pinned grok-bot version literal must not come back; the repo is the source"
fi

resolve_line="$(grep -n 'dnf5 --assumeyes repoquery' "${script}" | cut -d: -f1)"
install_line="$(grep -n 'dnf5 install -y grok-bot' "${script}" | cut -d: -f1)"
test -n "${resolve_line}" && test -n "${install_line}"
test "${resolve_line}" -lt "${install_line}" || fail "the repo must be resolved before installing"

# --- positive: build-time repo and key removed, vendor %post repo disabled ---
has_code 'rm -f "${GROK_BOT_KEY_FILE}" "${GROK_BOT_REPO_FILE}"'
has_code "sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/grok-bot.repo"
has_code "test \"\$(sed -n 's/^enabled=//p' /etc/yum.repos.d/grok-bot.repo)\" = \"0\""

# --- positive: installed paths from the packaged layout ----------------------
has_code 'test -x /usr/bin/grok-bot'
has_code 'test -f /usr/share/applications/grok-bot.desktop'

# --- negative: the retired pin and its drift tripwire stay retired ----------
# The unsigned download-page RPM and the stable-channel probe were replaced by the
# signed repo. Re-adding either would silently undo the signature anchor.
if printf '%s\n' "${code}" | grep -Fq 'grokbot/stable'; then
  fail "the build must not fetch the unsigned download-page artifact"
fi
if printf '%s\n' "${code}" | grep -Fq 'api2.cursor.sh'; then
  fail "the stable-channel drift tripwire is retired; the repo is the source now"
fi
if printf '%s\n' "${code}" | grep -Fq 'GROK_BOT_URL'; then
  fail "there is no pinned artifact URL any more"
fi
if printf '%s\n' "${code}" | grep -Fq 'GROK_BOT_RPM'; then
  fail "the local-file install path is retired; grok-bot comes from the repo"
fi

# --- negative: signature checking may never be bypassed ---------------------
if printf '%s\n' "${code}" | grep -Fq -- '--nogpgcheck'; then
  fail "Grok Bot must be signature-verified, never installed with --nogpgcheck"
fi
if printf '%s\n' "${code}" | grep -Eq '^repo?_?gpgcheck=0'; then
  fail "gpgcheck/repo_gpgcheck must stay enabled for the vendor repo"
fi

# --- negative: no sandbox override, no foreign packaging --------------------
if printf '%s\n' "${code}" | grep -Eq 'chmod[^#]*chrome-sandbox'; then
  fail "chrome-sandbox mode belongs to the vendor scriptlet, not this block"
fi
if printf '%s\n' "${code}" | grep -Fq -- '--no-sandbox'; then
  fail "no --no-sandbox flag may be added anywhere"
fi
if printf '%s\n' "${code}" | grep -Eqi '(flatpak|snap)[[:space:]]+(install|add|run)'; then
  fail "Grok Bot must come from the vendor repo, not flatpak/snap"
fi

# --- positive: placement and cleanup in this vendor's own module ------------
test "$(grep -c 'dnf5 clean all' "${script}")" -eq 1 || fail "dnf5 clean all must occur exactly once"
code_last="$(printf '%s\n' "${code}" | awk 'NF { last = $0 } END { print last }')"
[[ "${code_last}" == "dnf5 clean all" ]] || fail "dnf5 clean all must be the last executable line of the module"

grok_line="$(awk '/module-recipes\/grok-bot.yml/ { print NR }' "${recipe}")"
systemd_line="$(awk '/module-recipes\/systemd.yml/ { print NR }' "${recipe}")"
test -n "${grok_line}" && test -n "${systemd_line}" || fail "missing recipe module entry"
test "${grok_line}" -lt "${systemd_line}" || fail "grok-bot.yml must precede systemd.yml"

echo "check-grok-bot-install: OK"
