#!/usr/bin/env bash
set -euo pipefail

dnf_recipe="recipes/module-recipes/dnf.yml"
terra_recipe="recipes/module-recipes/terra.yml"
greetd="files/system/etc/greetd/config.toml"
systemd_recipe="recipes/module-recipes/systemd.yml"
dms_dropin="files/system/usr/lib/systemd/user/dms.service.d/override.conf"

# --- DankMaterialShell packages present in dnf.yml (from avengemedia/dms COPR +
#     danklinux coprdep). `dms` ships QML assets and the dms.service unit; the CLI
#     binary comes from separate dms-cli, which `dms` requires (dnf pulls it in
#     transitively, so it is deliberately not listed here). quickshell-git — not plain
#     quickshell — is required: the two conflict with each other, and `dms` needs the
#     -git build (see the note in dnf.yml). ---
grep -Fq "avengemedia/dms" "${dnf_recipe}"
for pkg in dms dms-greeter quickshell-git danksearch dankcalendar-git; do
  grep -Eq "^[[:space:]]*-[[:space:]]+${pkg}\$" "${dnf_recipe}" || {
    echo "dnf.yml missing DMS package: ${pkg}" >&2
    exit 1
  }
done

# --- noctalia must be gone: the shell is DMS now, and noctalia-qs conflicts with
#     upstream quickshell (both Provide quickshell). Scan every module so it
#     cannot reappear in a per-vendor script module either; a commented note is fine. ---
for f in recipes/module-recipes/*.yml; do
  if grep -v '^[[:space:]]*#' "$f" | grep -Fq "noctalia-shell"; then
    echo "noctalia-shell should no longer be installed in any module (${f}; a commented note is fine)" >&2
    exit 1
  fi
done
if grep -Eq "^[[:space:]]*-[[:space:]]+noctalia" "${dnf_recipe}"; then
  echo "noctalia packages should not be in dnf.yml" >&2
  exit 1
fi

# --- terra block now installs ONLY nwg-look + zed (adw-gtk3-theme moved to Fedora/dnf.yml) ---
grep -Fq "dnf5 install -y nwg-look zed" "${terra_recipe}"
grep -Fq "terra-bootstrap" "${terra_recipe}"
grep -Fq "sed -i 's/^enabled=0/enabled=1/' /etc/yum.repos.d/terra*.repo" "${terra_recipe}"
grep -Fq "sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/terra*.repo" "${terra_recipe}"
grep -Eq "^[[:space:]]*-[[:space:]]+adw-gtk3-theme\$" "${dnf_recipe}"
if grep -v '^[[:space:]]*#' "${terra_recipe}" | grep -Fq "adw-gtk3-theme"; then
  echo "adw-gtk3-theme should be in dnf.yml (Fedora), not the terra module (a commented note is fine)" >&2
  exit 1
fi

# --- DMS runs as a systemd user service (bound to graphical-session.target via niri) ---
grep -Eq "^[[:space:]]*-[[:space:]]+dms\.service\$" "${systemd_recipe}"
awk '/^user:/{u=1} u&&/enabled:/{e=1} e&&/-[[:space:]]+dms\.service/{found=1} END{exit !found}' "${systemd_recipe}" || {
  echo "dms.service must be under the systemd 'user: enabled:' scope" >&2
  exit 1
}

# Evaluate the image drop-in without starting a service or using the live manager.
dms_test_dir="$(mktemp -d)"
trap 'rm -rf "${dms_test_dir}"' EXIT
mkdir "${dms_test_dir}/dms.service.d"
printf '[Service]\nExecStart=/usr/bin/true\n' > "${dms_test_dir}/dms.service"
cp "${dms_dropin}" "${dms_test_dir}/dms.service.d/override.conf"
env SYSTEMD_UNIT_PATH="${dms_test_dir}" XDG_CURRENT_DESKTOP=niri \
  systemd-analyze --user --unit=dms.service condition
if env SYSTEMD_UNIT_PATH="${dms_test_dir}" XDG_CURRENT_DESKTOP=KDE \
  systemd-analyze --user --unit=dms.service condition; then
  echo "dms.service must not start in Plasma" >&2
  exit 1
fi
if env -u XDG_CURRENT_DESKTOP SYSTEMD_UNIT_PATH="${dms_test_dir}" \
  systemd-analyze --user --unit=dms.service condition; then
  echo "dms.service must not start without a desktop identity" >&2
  exit 1
fi

# --- greeter switched to dms-greeter running on niri, as the greeter user ---
grep -Fq 'command = "dms-greeter --command niri"' "${greetd}"
grep -Fq 'user = "greeter"' "${greetd}"
if grep -v '^[[:space:]]*#' "${greetd}" | grep -Fq "tuigreet"; then
  echo "tuigreet command should be replaced by dms-greeter (a commented revert-note is fine)" >&2
  exit 1
fi

# --- dnf.yml runs before terra.yml so upstream quickshell is installed before the
#     terra block runs (prevents any terra-quickshell/noctalia-qs from winning) ---
recipe="recipes/recipe.yml"
dnf_line="$(awk '/module-recipes\/dnf.yml/ { print NR }' "${recipe}")"
terra_line="$(awk '/module-recipes\/terra.yml/ { print NR }' "${recipe}")"
test -n "${dnf_line}" && test -n "${terra_line}" || {
  echo "missing dnf.yml or terra.yml in recipe.yml" >&2
  exit 1
}
test "${dnf_line}" -lt "${terra_line}"

echo "check-dms-install: OK"
