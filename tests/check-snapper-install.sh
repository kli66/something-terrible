#!/usr/bin/env bash
set -euo pipefail

dnf="recipes/module-recipes/dnf.yml"
systemd="recipes/module-recipes/systemd.yml"
conf="files/system/etc/snapper/configs/home"
init_unit="files/system/etc/systemd/system/snapper-home-init.service"
init_script="files/system/usr/libexec/snapper-home-init.sh"

# snapper + GUI come from the fedora repo -> dnf.yml install list
grep -Eq '^\s*- snapper\s*$' "${dnf}"
grep -Eq '^\s*- btrfs-assistant\s*$' "${dnf}"

# timers + first-boot subvolume init are enabled
grep -Fq "snapper-timeline.timer" "${systemd}"
grep -Fq "snapper-cleanup.timer" "${systemd}"
grep -Fq "snapper-home-init.service" "${systemd}"

# config targets /var/home with the lean, cache-aware timeline retention
grep -Fq 'SUBVOLUME="/var/home"' "${conf}"
grep -Fq 'FSTYPE="btrfs"' "${conf}"
grep -Fq 'TIMELINE_CREATE="yes"' "${conf}"
grep -Fq 'TIMELINE_LIMIT_HOURLY="0"' "${conf}"
grep -Fq 'TIMELINE_LIMIT_DAILY="7"' "${conf}"

# first-boot unit is guarded to run once and creates the subvolume
grep -Fq 'ConditionPathExists=!/var/home/.snapshots' "${init_unit}"
grep -Fq '/usr/libexec/snapper-home-init.sh' "${init_unit}"
grep -Fq 'btrfs subvolume create' "${init_script}"

echo "check-snapper-install: OK"
