#!/usr/bin/env bash
set -euo pipefail

dnf_recipe="recipes/module-recipes/dnf.yml"
script="recipes/module-recipes/scripts.yml"
greetd="files/system/etc/greetd/config.toml"
systemd_recipe="recipes/module-recipes/systemd.yml"

# --- DankMaterialShell packages present in dnf.yml (from avengemedia/dms COPR +
#     danklinux coprdep). `dms` ships the `dms` CLI itself (no separate dms-cli), and
#     quickshell-git — not plain quickshell 0.3.0 — is required (they Provide+Conflict
#     quickshell and `dms` needs the -git build; see the note in dnf.yml). ---
grep -Fq "avengemedia/dms" "${dnf_recipe}"
for pkg in dms dms-greeter quickshell-git danksearch dankcalendar-git; do
  grep -Eq "^[[:space:]]*-[[:space:]]+${pkg}\$" "${dnf_recipe}" || {
    echo "dnf.yml missing DMS package: ${pkg}" >&2
    exit 1
  }
done

# --- noctalia must be gone: the shell is DMS now, and noctalia-qs conflicts with
#     upstream quickshell (both Provide quickshell). ---
if grep -v '^[[:space:]]*#' "${script}" | grep -Fq "noctalia-shell"; then
  echo "noctalia-shell should no longer be installed in scripts.yml (a commented note is fine)" >&2
  exit 1
fi
if grep -Eq "^[[:space:]]*-[[:space:]]+noctalia" "${dnf_recipe}"; then
  echo "noctalia packages should not be in dnf.yml" >&2
  exit 1
fi

# --- terra block now installs ONLY nwg-look + zed (adw-gtk3-theme moved to Fedora/dnf.yml) ---
grep -Fq "dnf5 install -y nwg-look zed" "${script}"
grep -Eq "^[[:space:]]*-[[:space:]]+adw-gtk3-theme\$" "${dnf_recipe}"
if grep -v '^[[:space:]]*#' "${script}" | grep -Fq "adw-gtk3-theme"; then
  echo "adw-gtk3-theme should be in dnf.yml (Fedora), not the terra block in scripts.yml (a commented note is fine)" >&2
  exit 1
fi

# --- DMS runs as a systemd user service (bound to graphical-session.target via niri) ---
grep -Eq "^[[:space:]]*-[[:space:]]+dms\.service\$" "${systemd_recipe}"
awk '/^user:/{u=1} u&&/enabled:/{e=1} e&&/-[[:space:]]+dms\.service/{found=1} END{exit !found}' "${systemd_recipe}" || {
  echo "dms.service must be under the systemd 'user: enabled:' scope" >&2
  exit 1
}

# --- greeter switched to dms-greeter running on niri, as the greeter user ---
grep -Fq 'command = "dms-greeter --command niri"' "${greetd}"
grep -Fq 'user = "greeter"' "${greetd}"
if grep -v '^[[:space:]]*#' "${greetd}" | grep -Fq "tuigreet"; then
  echo "tuigreet command should be replaced by dms-greeter (a commented revert-note is fine)" >&2
  exit 1
fi

# --- dnf.yml runs before scripts.yml so upstream quickshell is installed before the
#     terra block runs (prevents any terra-quickshell/noctalia-qs from winning) ---
recipe="recipes/recipe.yml"
dnf_line="$(awk '/module-recipes\/dnf.yml/ { print NR }' "${recipe}")"
scripts_line="$(awk '/module-recipes\/scripts.yml/ { print NR }' "${recipe}")"
test "${dnf_line}" -lt "${scripts_line}"

echo "check-dms-install: OK"
