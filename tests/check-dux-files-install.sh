#!/usr/bin/env bash
set -euo pipefail

dnf_recipe="recipes/module-recipes/dnf.yml"
systemd_recipe="recipes/module-recipes/systemd.yml"

# --- Dux Files (dfiles) from avengemedia/danklinux, which is enabled transitively as
#     the coprdep of avengemedia/dms. Stable dux-files only: dux-files-git declares
#     Conflicts against it (both Provide dfiles), so exactly one may be listed, and a
#     -git build would churn the dnf layer on every upstream push. ---
grep -Eq "^[[:space:]]*-[[:space:]]+dux-files\$" "${dnf_recipe}" || {
  echo "dnf.yml missing Dux Files package: dux-files" >&2
  exit 1
}
if grep -v '^[[:space:]]*#' "${dnf_recipe}" | grep -Eq "^[[:space:]]*-[[:space:]]+dux-files-git[[:space:]]*\$"; then
  echo "dux-files-git Conflicts with dux-files; install exactly one" >&2
  exit 1
fi

# --- dux-files Requires (quickshell-git or quickshell). The image pins the -git build,
#     and plain quickshell conflicts with it, so it must not be listed on its own. ---
grep -Eq "^[[:space:]]*-[[:space:]]+quickshell-git\$" "${dnf_recipe}"
if grep -v '^[[:space:]]*#' "${dnf_recipe}" | grep -Eq "^[[:space:]]*-[[:space:]]+quickshell[[:space:]]*\$"; then
  echo "plain quickshell must not be installed alongside quickshell-git" >&2
  exit 1
fi

# --- grouped with the Dux stack, not appended somewhere unrelated in the list ---
dms_line="$(awk '/^[[:space:]]*-[[:space:]]+dms$/ { print NR; exit }' "${dnf_recipe}")"
dux_line="$(awk '/^[[:space:]]*-[[:space:]]+dux-files$/ { print NR; exit }' "${dnf_recipe}")"
test -n "${dms_line}"
test -n "${dux_line}"
test "${dux_line}" -gt "${dms_line}"

# --- resident daemon: shipped disabled by the package, enabled here in the user scope
#     so it is bound to graphical-session.target in every session ---
grep -Eq "^[[:space:]]*-[[:space:]]+dfiles\.service\$" "${systemd_recipe}"
awk '/^user:/{u=1} u&&/enabled:/{e=1} e&&/-[[:space:]]+dfiles\.service/{found=1} END{exit !found}' "${systemd_recipe}" || {
  echo "dfiles.service must be under the systemd 'user: enabled:' scope" >&2
  exit 1
}

# --- no baked desktop defaults. The directory handler is the user's
#     `xdg-mime default dev.duxlabs.files.desktop inode/directory` and the file-chooser
#     backend is `dfiles portal install`; both write per-user files. A mimeapps.list or
#     portals.conf under files/system would decide them for every user of the image, so
#     its reappearance is a regression, not an improvement. ---
if [ -e files/system/etc/xdg/mimeapps.list ]; then
  echo "files/system/etc/xdg/mimeapps.list bakes a desktop default; the handler stays user-owned" >&2
  exit 1
fi
if find files/system -type f \( -name '*mimeapps.list*' -o \
     -name 'portals.conf' -o -name '*-portals.conf' \) | grep -q .; then
  echo "a baked mimeapps.list/portals.conf would decide desktop defaults for every user" >&2
  exit 1
fi

echo "check-dux-files-install: OK"
