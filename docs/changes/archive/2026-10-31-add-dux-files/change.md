---
id: add-dux-files
status: landed
persistence: ephemeral
depends_on:
files_owned:
  - docs/changes/add-dux-files/change.md
  - recipes/module-recipes/dnf.yml
  - recipes/module-recipes/systemd.yml
  - tests/check-dux-files-install.sh
  - AGENTS.md
accepted_at: 2026-10-31
started_at: 2026-10-31
landed_at: 2026-10-31
archive_path: docs/changes/archive/2026-10-31-add-dux-files
---
# Add Dux Files (dfiles) as a resident file manager

Status: Landed · 2026-10-31

**Upstream dependencies:** `dux-files` and `dux-files-git` are published in COPR
`avengemedia/danklinux`, which this image already reaches transitively as the coprdep of
`avengemedia/dms` — the same path `danksearch`, `dankcalendar-git` and `dms-greeter` already
resolve through, so no new `copr:` entry is needed. Both packages build for `fedora-44-x86_64`
(COPR builds succeeded at proposal time). `Requires: (quickshell-git or quickshell)` is satisfied
by the `quickshell-git` pin, and `qt6-qtdeclarative` is already on the image. The newer
`duxlabs/dux-repo` COPR mirrors the package under Dux Labs' rebranded names (`dux-search`,
`dux-calendar`, `dux-greeter`), but that project still states its repos are not ready for
production and points back to `avengemedia`; migrating repo and package names is a separate
change, not part of this one.
**Dependents:** None. `docs/self-build-todo.md` is unaffected, no kargs are involved, and no
other change folder waits on this one.

## Why

DMS 2.0 ("Heisenberg") rebranded DankMaterialShell to Dux Shell and the suite to Dux Labs, and
shipped Dux Files (`dfiles`) as its first-party file manager: a pure-Go daemon with an embedded
Quickshell UI that follows Dux Shell's colors when DMS runs, handles
`org.freedesktop.FileManager1`, and ships a `xdg-desktop-portal` file-chooser backend. It is the
shell-consistent file manager for a niri + Dux Shell image, and it is available from a repo the
image already trusts for its desktop stack.

The image currently ships `dolphin` from the Kinoite base and nothing else that owns
`inode/directory` under a niri session. Installing `dfiles` and keeping its daemon resident is
what makes "open folder" and reveal-in-file-manager behave the way the shell's own UI implies,
without the image deciding anything on the user's behalf.

## Design constraints

1. **The image installs capability, not preferences.** `mimeapps.list` and `xdg-desktop-portal`
   routing stay user-owned. Nothing in `/etc/xdg` or `files/system` preselects `dfiles`. This
   is upstream's own packaging stance: the package ships `dfiles.portal` and deliberately does
   not ship a `portals.conf` that prefers it.
2. **Streams, not names.** `dux-files` and `dux-files-git` `Conflicts:` each other and both
   `Provides: dfiles`. Install exactly one. This change takes the stable, tag-tracked
   `dux-files`: a `-git` package re-resolves to a new upstream commit on every image build,
   which is layer churn `docs/layer-optimization.md` deliberately avoids for anything that does
   not need it. `quickshell-git` needs it; a file manager does not.
3. **The resident daemon is the one non-default worth taking.** `dfiles.service` ships disabled
   and is the documented switch for instant windows plus immediate answers to `FileManager1`
   and portal requests. It also settles the `org.freedesktop.FileManager1` activation race by
   construction: a running Dux Files holds the name, so `dolphin`'s
   `org.kde.dolphin.FileManager1.service` in the same `/usr/share/dbus-1/services/` directory
   never gets consulted. Accepted cost: a second Quickshell process for the session, and
   `--keep-running` semantics where closing the last window hides it instead of quitting.

## What changes

### Δ ADDED

- `dux-files` in the Dux block of `recipes/module-recipes/dnf.yml`, with a comment recording the
  `dux-files-git` conflict, the `quickshell-git` requirement, and that `gvfs` arrives as a weak
  dep (`Recommends:`) — needed for `trash://` and network shares, absent on the Kinoite baseline.
- `dfiles.service` in the user scope of `recipes/module-recipes/systemd.yml`.
- `tests/check-dux-files-install.sh` asserting the package, the absence of its conflicting
  sibling, the user-scope unit, and the absence of any baked desktop-default override.
- A "desktop defaults stay user-owned" line in the `AGENTS.md` conventions, naming the two
  opt-in seams so a later agent does not helpfully bake them.

### Δ MODIFIED

- `AGENTS.md`: the `dnf.yml` module description mentions Dux Files; the suite count goes 9 → 10.

### Δ REMOVED

- None. `dolphin` stays installed and remains launchable.

## Not doing (and why)

- **No `/etc/xdg/mimeapps.list`.** It would decide the handler for every user. The seam is the
  per-user file `~/.config/mimeapps.list`, written by
  `xdg-mime default dev.duxlabs.files.desktop inode/directory` (same for
  `x-scheme-handler/trash|sftp|smb` and the archive types the desktop entry claims). An
  administrator who wants it machine-wide can create `/etc/xdg/mimeapps.list` on the deployed
  system — `/etc` is the mutable, update-persistent layer on this atomic image, and
  `XDG_CONFIG_DIRS` outranks `/usr/share`. Note for context: the baseline's
  `inode/directory` default lives in `/usr/share/applications/kde-mimeapps.list`
  (`org.kde.dolphin.desktop`), which is desktop-scoped and does not apply to a `niri`
  `XDG_CURRENT_DESKTOP`; the generic `mimeapps.list` names `org.gnome.Nautilus`, which is not
  installed. So today nothing resolves the type under niri, and the base image already leaves
  this to the user.
- **No `portals.conf` of any kind.** Under niri, `xdg-desktop-portal` reads
  `/usr/share/xdg-desktop-portal/niri-portals.conf` (owned by the `niri` rpm), which sets
  `default=gnome;gtk;` — so the file-chooser backend on this image is gtk, not the KDE portal
  we also install. Overriding that image-wide means shipping a full
  `/etc/xdg/xdg-desktop-portal/niri-portals.conf`, which *replaces* rather than merges into the
  packaged file and would have to be re-synced on every niri bump. The seam is upstream's
  per-user one: `dfiles portal install` (or Settings → General → *Use Dux Files for open and save
  dialogs*) writes `~/.config/xdg-desktop-portal/niri-portals.conf`, keeps the previous backend
  as fallback, preserves the other keys, and is reversible with `dfiles portal uninstall` /
  `dfiles portal status`. It takes effect after
  `systemctl --user restart xdg-desktop-portal.service`.
- **No `ffmpegthumbnailer` / `poppler-utils`.** They enable video and PDF thumbnails
  (`Suggests:`). Add them only if wanted; they are unrelated to the daemon or defaults.

## Tasks

1. Add `dux-files` to the Dux block in `recipes/module-recipes/dnf.yml` with the rationale
   comment described above. Do not add `dux-files-git`, and do not add a `avengemedia/danklinux`
   `copr:` entry — the coprdep path already covers it.
2. Enable `dfiles.service` in the `user: enabled:` list of
   `recipes/module-recipes/systemd.yml` with a comment recording the resident-daemon rationale
   and the `FileManager1` ordering argument.
3. Add `tests/check-dux-files-install.sh` (positive: package in `dnf.yml`, unit under
   `user: enabled:`; negative: no `dux-files-git`, no plain `quickshell`, no
   `files/system/etc/xdg/mimeapps.list`, no `portals` `.conf` under `files/system`).
4. Update `AGENTS.md`: Dux Files in the `dnf.yml` bullet, suite count 9 → 10, and the
   user-owned-defaults convention with the two seams named.
5. Deploy and verify at runtime (below), and record the evidence in this file.

## Verify

**Exit evidence (2026-10-31).** Package resolution was checked against the live repo metadata
rather than assumed: `avengemedia/danklinux/fedora-44-x86_64/repodata/…primary.xml.gz` lists
`dux-files 2.0.0-1.fc44` (`Packages/d/dux-files-2.0.0-1.fc44.x86_64.rpm`, `Requires` the
`mimehandler(…)` set and `(quickshell-git or quickshell)`), alongside `dux-files-git` builds —
confirming both that the stable name resolves on `fedora-44` and that the `-git` sibling really is
a separate conflicting package. `bash tests/check-*.sh` is 10/10 green, including the new
`tests/check-dux-files-install.sh`. Its negative half was mutation-tested: planting
`files/system/etc/xdg/mimeapps.list` fails the run with "bakes a desktop default", and removing it
restores green. `yamllint` reports no syntax errors on `recipes/recipe.yml`, `dnf.yml`, or
`systemd.yml` (only the repo's pre-existing line-length/document-start style complaints).
`doc-contract check --repo-root . --offline` is clean for this change.

`dolphin` is deliberately left installed, and no `mimeapps.list` or `portals.conf` was added: the
handler and the portal backend remain per-user seams. Runtime items below are the deploy-time
confirmations, which cannot be produced from the source tree — they stay listed rather than
claimed as done.

Build-time / repo:

```bash
for t in tests/check-*.sh; do bash "$t"; done   # 10 files, all green
doc-contract check --repo-root . --offline      # 0 errors, no new warnings
```

Runtime, after the image is deployed and the niri session restarted:

```bash
systemctl --user status dfiles.service                      # active (running), session scope
systemctl --user cat dfiles.service | grep -F 'keep-running'
dfiles version
busctl --user status org.freedesktop.FileManager1           # owner is dfiles, not dolphin
dfiles ipc system.capabilities                              # bwrap/gvfs/thumbnailers found
```

- Confirm the greeter session does not leave a second `dfiles` running: because the unit is
  `WantedBy=graphical-session.target` and enabled globally it reaches the `greeter` user too, and
  `dms-greeter --command niri` runs plain `niri` rather than `niri-session`. If it does appear,
  harden with a drop-in mirroring `dms.service`'s `Requisite=graphical-session.target`.
- Confirm the seams remain user-owned and functional, without changing the image: run
  `xdg-mime default dev.duxlabs.files.desktop inode/directory` and check
  `~/.config/mimeapps.list`; run `dfiles portal install`, restart `xdg-desktop-portal`, and
  confirm a portal-driven open dialog comes from `dfiles`; then `dfiles portal status`.
- Leave the defaults unset afterwards if the operator does not want them — that is the point of
  the seam, not an unfinished task.
