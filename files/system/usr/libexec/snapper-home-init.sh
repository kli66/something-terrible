#!/usr/bin/bash
# First-boot initialization of the snapper snapshot store for /var/home.
#
# The .snapshots subvolume cannot be baked into the image: /var/home is the
# user's data partition, absent at image-build time. This runs once (guarded
# both here and by the unit's ConditionPathExists) and then self-skips.
set -oue pipefail

target="/var/home/.snapshots"

# Idempotency guard (the systemd unit also gates on this path).
if [ -e "${target}" ]; then
  exit 0
fi

# Must be a btrfs *subvolume*, not a plain dir: snapshots do not cross
# subvolume boundaries, so this keeps .snapshots out of its own snapshots and
# gives snapper the layout it expects.
/usr/sbin/btrfs subvolume create "${target}"
chown root:root "${target}"
chmod 0750 "${target}"

# Best-effort SELinux label so the snapper timers can write here on an
# enforcing system (Kinoite default). Fall back to the parent context if the
# snapperd type is unavailable; never fail the unit over labelling.
if command -v chcon >/dev/null 2>&1; then
  chcon -t snapperd_data_t "${target}" 2>/dev/null \
    || chcon --reference=/var/home "${target}" 2>/dev/null \
    || true
fi
