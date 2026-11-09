#!/usr/bin/env bash
set -euo pipefail

rules="files/system/usr/share/fonts/cjk-defaults/cjk-default.conf"
flatpak_conf="files/system/usr/share/fonts/cjk-defaults/flatpak-fonts.conf"
host_conf="files/system/etc/fonts/conf.d/99-cjk-default.conf"
unit="files/system/etc/systemd/system/flatpak-cjk-fontconfig.service"
dnf="recipes/module-recipes/dnf.yml"
systemd="recipes/module-recipes/systemd.yml"
recipe="recipes/recipe.yml"

fail() {
  echo "check-cjk-fontconfig: $*" >&2
  exit 1
}

for f in "$rules" "$flatpak_conf" "$host_conf" "$unit"; do
  test -f "$f" || fail "missing ${f}"
done

# --- Host and Flatpak load the same rules file, not two drifting copies. ---
grep -Fq '<include ignore_missing="yes">/usr/share/fonts/cjk-defaults/cjk-default.conf</include>' \
  "$host_conf" || fail "host conf.d does not include the shared rules"
grep -Fq '<include ignore_missing="yes">/etc/fonts/fonts.conf</include>' "$flatpak_conf" ||
  fail "Flatpak wrapper does not include the runtime config"
grep -Fq '<dir>/run/host/fonts</dir>' "$flatpak_conf" ||
  fail "Flatpak wrapper does not add the host font dir"
grep -Fq '<include ignore_missing="yes">/run/host/fonts/cjk-defaults/cjk-default.conf</include>' \
  "$flatpak_conf" || fail "Flatpak wrapper does not include the shared rules"

# --- Every locale and generic family is covered exactly once per family. ---
for lang in zh-cn zh-sg zh-tw zh-hk zh-mo ja ko; do
  count="$(grep -Fc "<test name=\"lang\"><string>${lang}</string></test>" "$rules" || true)"
  test "$count" -eq 3 || fail "expected 3 rules for lang=${lang}, found ${count}"
done
for family in sans-serif serif monospace; do
  count="$(grep -Fc "<test name=\"family\"><string>${family}</string></test>" "$rules" || true)"
  test "$count" -eq 7 || fail "expected 7 rules for family=${family}, found ${count}"
done
for family in \
  'Noto Sans CJK SC' 'Noto Serif CJK SC' 'Noto Sans Mono CJK SC' \
  'Noto Sans CJK TC' 'Noto Serif CJK TC' 'Noto Sans Mono CJK TC' \
  'Noto Sans CJK HK' 'Noto Serif CJK HK' 'Noto Sans Mono CJK HK' \
  'Noto Sans CJK JP' 'Noto Serif CJK JP' 'Noto Sans Mono CJK JP' \
  'Noto Sans CJK KR' 'Noto Serif CJK KR' 'Noto Sans Mono CJK KR'; do
  grep -Fq "<string>${family}</string>" "$rules" || fail "missing family ${family}"
done

# --- prepend_first, never prepend: DMS strongly prepends Inter ahead of the
#     generic family, and plain prepend inserts before the matched value. ---
count="$(grep -Fc 'mode="prepend_first" binding="strong"' "$rules" || true)"
test "$count" -eq 21 || fail "expected 21 prepend_first edits, found ${count}"
if grep -Fq 'mode="prepend"' "$rules"; then
  fail "plain prepend loses to the DMS Inter override; use prepend_first"
fi

# --- The Flatpak override is seeded at boot; no /var content is shipped. ---
grep -Fq 'flatpak override --system' "$unit" || fail "unit does not write a system override"
grep -Fq -- '--env=FONTCONFIG_FILE=/run/host/fonts/cjk-defaults/flatpak-fonts.conf' "$unit" ||
  fail "unit does not point FONTCONFIG_FILE at the host font mount"
grep -Fq 'ConditionPathExists=!/var/lib/flatpak/.something-terrible-cjk-fontconfig-seeded' "$unit" ||
  fail "unit is not gated to a one-time seed"
grep -Fq 'touch /var/lib/flatpak/.something-terrible-cjk-fontconfig-seeded' "$unit" ||
  fail "unit does not write the seed marker"
grep -Fq 'WantedBy=multi-user.target' "$unit" || fail "unit is not a system service"
if grep -Fq -- '--filesystem=' "$unit"; then
  fail "no filesystem grant is needed; Flatpak rejects /etc and /usr"
fi
if find files/system -path '*/var/lib/flatpak*' -print -quit | grep -q .; then
  fail "do not bake /var/lib/flatpak; seed the override from the system unit"
fi

# --- The unit is under the system scope, not the user scope. ---
awk '
  /^system:/ { system_scope = 1 }
  system_scope && /^  enabled:/ { enabled = 1; next }
  system_scope && /^  disabled:/ { enabled = 0 }
  enabled && /flatpak-cjk-fontconfig\.service/ { found = 1 }
  END { exit !found }
' "$systemd" || fail "flatpak-cjk-fontconfig.service must be under system > enabled"

# --- The family names come from the combined CJK RPMs, not the Google Fonts
#     per-language subsets that fonts.yml downloads. ---
for pkg in \
  google-noto-sans-cjk-vf-fonts \
  google-noto-serif-cjk-vf-fonts \
  google-noto-sans-mono-cjk-vf-fonts; do
  grep -Eq "^[[:space:]]*-[[:space:]]+${pkg}\$" "$dnf" || fail "dnf.yml missing ${pkg}"
done

# --- No user-installed font is baked as a default. ---
if grep -RFq -e 'FangSong' -e 'STSong' -e 'STFangsong' files/system; then
  fail "user-installed CJK fonts must not be baked as defaults"
fi

# --- files.yml still runs before systemd.yml. ---
files_line="$(awk '/module-recipes\/files.yml/ { print NR; exit }' "$recipe")"
systemd_line="$(awk '/module-recipes\/systemd.yml/ { print NR; exit }' "$recipe")"
test -n "$files_line" && test -n "$systemd_line" || fail "missing files.yml or systemd.yml"
test "$files_line" -lt "$systemd_line" || fail "files.yml must precede systemd.yml"

echo "check-cjk-fontconfig: OK"
