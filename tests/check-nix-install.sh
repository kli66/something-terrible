#!/usr/bin/env bash
set -euo pipefail

dnf="recipes/module-recipes/dnf.yml"
systemd_recipe="recipes/module-recipes/systemd.yml"
recipe="recipes/recipe.yml"
mount_unit="files/system/etc/systemd/system/nix-store-mount.service"
mount_helper="files/system/usr/libexec/mount-nix-store"

fail() {
	echo "check-nix-install: $*" >&2
	exit 1
}

[[ -x "${mount_helper}" ]] || fail "Nix mount helper is missing or not executable"
[[ -f "${mount_unit}" ]] || fail "Nix mount unit is missing"

grep -Eq '^[[:space:]]*-[[:space:]]+nix[[:space:]]*$' "${dnf}" || fail "nix package is not installed"
grep -Eq '^[[:space:]]*-[[:space:]]+nix-daemon[[:space:]]*$' "${dnf}" || fail "nix-daemon package is not installed"

# Keep the store in persistent /var and expose it at the RPM-provided /nix.
grep -Fq 'install -d -m 0755 /var/lib/nix' "${mount_helper}" || fail "persistent store is not created under /var"
grep -Fq 'test -d /nix' "${mount_helper}" || fail "helper does not require the packaged /nix mount point"
grep -Fq 'mount --bind /var/lib/nix /nix' "${mount_helper}" || fail "persistent store is not bind-mounted to /nix"

# The bind mount must precede the RPM's tmpfiles setup and daemon startup.
grep -Fxq 'Before=systemd-tmpfiles-setup.service' "${mount_unit}" || fail "mount is not ordered before tmpfiles"
grep -Fxq 'Before=nix-daemon.service' "${mount_unit}" || fail "mount is not ordered before nix-daemon"
grep -Fxq 'RequiresMountsFor=/var' "${mount_unit}" || fail "mount unit does not require persistent /var"
grep -Fxq 'WantedBy=sysinit.target' "${mount_unit}" || fail "mount unit is not part of early boot"

awk '/^system:/{system_scope=1; next} /^user:/{system_scope=0} system_scope&&/^[[:space:]]+enabled:/{enabled_scope=1; next} system_scope&&enabled_scope&&/-[[:space:]]+nix-store-mount\.service/{found=1} END{exit !found}' "${systemd_recipe}" || fail "nix-store-mount.service is not enabled in system scope"
awk '/^system:/{system_scope=1; next} /^user:/{system_scope=0} system_scope&&/^[[:space:]]+enabled:/{enabled_scope=1; next} system_scope&&enabled_scope&&/-[[:space:]]+nix-daemon\.service/{found=1} END{exit !found}' "${systemd_recipe}" || fail "nix-daemon.service is not enabled in system scope"

files_line="$(awk '/module-recipes\/files.yml/ { print NR }' "${recipe}")"
dnf_line="$(awk '/module-recipes\/dnf.yml/ { print NR }' "${recipe}")"
systemd_line="$(awk '/module-recipes\/systemd.yml/ { print NR }' "${recipe}")"
[[ -n "${files_line}" && -n "${dnf_line}" && -n "${systemd_line}" ]] || fail "missing recipe module entry"
((files_line < dnf_line && dnf_line < systemd_line)) || fail "files and dnf modules must precede systemd enablement"

if rg -q 'install\.determinate\.systems|install-nix-[^ ]*' recipes files/system; then
	fail "external Nix installer logic should not be baked into the image"
fi

echo "check-nix-install: OK"
