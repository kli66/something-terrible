---
id: add-cjk-font-defaults
status: landed
persistence: ephemeral
depends_on:
files_owned:
  - docs/changes/add-cjk-font-defaults/change.md
  - files/system/usr/share/fonts/cjk-defaults/cjk-default.conf
  - files/system/usr/share/fonts/cjk-defaults/flatpak-fonts.conf
  - files/system/etc/fonts/conf.d/99-cjk-default.conf
  - files/system/etc/systemd/system/flatpak-cjk-fontconfig.service
  - recipes/module-recipes/dnf.yml
  - recipes/module-recipes/systemd.yml
  - tests/check-cjk-fontconfig.sh
  - AGENTS.md
accepted_at: 2026-11-09
started_at: 2026-11-09
landed_at: 2026-11-09
archive_path: docs/changes/archive/2026-11-09-add-cjk-font-defaults
---
# Add image-wide CJK font defaults for host and Flatpak

Status: Landed · 2026-11-09

**Entry/exit reconciliation (2026-11-09).** Checked against the live Kinoite 44 system and Flatpak
1.18.4. The base image already ships the three combined Noto CJK RPMs, and `fc-match` returns their
family names. Flatpak rejects `/etc` and `/usr` as `--filesystem` sources ("Path \"/etc\" is reserved
by Flatpak"), so the config rides the automatic `/usr/share/fonts` → `/run/host/fonts` mount instead.
A nested `FONTCONFIG_FILE` under the equivalent `/run/host/user-fonts` mount was parsed inside a
Spotify sandbox and changed `sans-serif:lang=zh-cn` from `FangSong` to `Noto Sans CJK SC`; the
system-override syntax was exercised against a temporary ostree-backed `FLATPAK_SYSTEM_DIR`, which
wrote the expected `[Context]`/`[Environment]` file. Host rule verification covered all 21
locale/family combinations and left plain `sans-serif`/`serif`/`monospace` unchanged.
`tests/check-cjk-fontconfig.sh` and the full 13-file suite pass; `doc-contract check` reports 0
errors and the five pre-existing `add-skillshare-manager` baseline warnings; `systemd-analyze verify`
accepts the unit. The CI-built image and a booted `/run/host/fonts` read remain the CI/operator gate
(the exact host-font mount is observed in Flatpak's mount table, not rebuilt locally). The one-time
migration for an existing user-level `FONTCONFIG_FILE` override is recorded under Verify.

**Upstream dependencies:** The base Kinoite 44 tree already ships the combined Noto CJK OTC
families (`google-noto-sans-cjk-vf-fonts`, `google-noto-serif-cjk-vf-fonts`,
`google-noto-sans-mono-cjk-vf-fonts`); this change makes that dependency explicit in `dnf.yml`
because the new rules reference the `Noto * CJK *` family names, not the per-language Google Fonts
downloads in `fonts.yml`. Flatpak's system-wide override store is `/var/lib/flatpak/overrides/global`;
`/var` is machine-local and is not refreshed from the image on rebase, so the override must be
seeded by a first-boot oneshot. Flatpak rejects `--filesystem=/etc` and `/usr` as reserved; the
config therefore rides Flatpak's existing host-font mount, `/usr/share/fonts` → `/run/host/fonts`.
**Dependents:** None. No other change folder or roadmap item depends on this one.
**Files owned:** `docs/changes/add-cjk-font-defaults/change.md`; the shared rules and Flatpak
wrapper under `files/system/usr/share/fonts/cjk-defaults/`; the host include
`files/system/etc/fonts/conf.d/99-cjk-default.conf`; the
`files/system/etc/systemd/system/flatpak-cjk-fontconfig.service` unit; `recipes/module-recipes/dnf.yml`
and `systemd.yml`; `tests/check-cjk-fontconfig.sh`; and the architecture/test-count notes in
`AGENTS.md`. User font files, per-user Flatpak overrides, and the user's existing
`~/.local/share/flatpak-fonts` workaround are explicitly not owned.

## Why

The image now exposes several user-installed CJK fonts (FangSong/STSong/STFangsong) through
`~/.local/share/fonts`, and Flatpak exposes that tree to every sandbox as `/run/host/user-fonts`.
Neither the host nor the freedesktop runtime has a language-specific preference for those fonts, so
`fontconfig` falls through to scan order: `fc-match 'sans-serif:lang=zh-cn'` inside a Flatpak
sandbox returned `FangSong` before this change. The host has a separate override
(`~/.config/fontconfig/conf.d/99-dms-theme-sync.conf`) that pins `sans-serif`/`serif` to Inter; a
plain `prepend` is inserted before the matching `sans-serif` value and still loses to Inter, while
`prepend_first` inserts at the head of the family list and wins only for the `lang`-qualified
patterns.

The host and Flatpak need different delivery paths. Host apps read `/etc/fonts/conf.d` from the
image. Flatpak apps read the runtime's `/etc/fonts`, not the host's; the only host path Flatpak
guarantees inside the sandbox is the host font tree at `/run/host/fonts`. A `FONTCONFIG_FILE`
pointing into that tree works without granting `/etc` or `/usr` (both are reserved by Flatpak).
The override that sets `FONTCONFIG_FILE` is a system Flatpak setting stored in `/var`, so it must be
seeded once at boot rather than copied into the image's `/var` (which is not applied on rebase).

## What changes

### Δ ADDED

- `files/system/usr/share/fonts/cjk-defaults/cjk-default.conf`: one shared set of
  `lang`-qualified, strong `prepend_first` rules for `sans-serif`, `serif`, and `monospace` covering
  `zh-cn`/`zh-sg` (SC), `zh-tw` (TC), `zh-hk`/`zh-mo` (HK), `ja`, and `ko`. It lives under the host
  font tree so Flatpak's automatic `/run/host/fonts` mount makes it visible inside sandboxes.
- `files/system/usr/share/fonts/cjk-defaults/flatpak-fonts.conf`: the Flatpak
  `FONTCONFIG_FILE`. It includes the runtime's `/etc/fonts/fonts.conf`, adds
  `<dir>/run/host/fonts</dir>` for runtimes whose prebuilt cache skips the host tree, and includes
  the shared rules as the last parse.
- `files/system/etc/fonts/conf.d/99-cjk-default.conf`: a thin host include of the same shared rules,
  loaded after Fedora's and the user's fontconfig configs.
- `files/system/etc/systemd/system/flatpak-cjk-fontconfig.service`: a once-per-machine oneshot that
  runs `flatpak override --system --env=FONTCONFIG_FILE=/run/host/fonts/cjk-defaults/flatpak-fonts.conf`
  and writes a marker under `/var/lib/flatpak`. The marker makes the seed a one-time provisioning
  step; later user edits to the system override are not overwritten on every boot.
- `tests/check-cjk-fontconfig.sh`: intent test for the shared rules, the include paths, the
  first-boot seed, the CJK RPM names, and the absence of baked `/var` content.

### Δ MODIFIED

- `recipes/module-recipes/dnf.yml`: add the three combined Noto CJK RPMs so the family names used by
  the rules are guaranteed independently of base-image drift.
- `recipes/module-recipes/systemd.yml`: enable `flatpak-cjk-fontconfig.service` in the system scope.
- `AGENTS.md`: record the host/Flatpak split, the `/run/host/fonts` delivery path, the `/var`
  first-boot seed rule, and the new test count.

### Δ REMOVED

- None. The existing user-level `~/.local/share/flatpak` workaround is not touched by the image;
  the one-time migration is an operator action after the image lands.

## Tasks

1. Add the shared rules file, the Flatpak wrapper, and the host include. — done.
2. Add the first-boot `flatpak-cjk-fontconfig.service` and enable it in `systemd.yml`. — done.
3. Add the Noto CJK RPMs to `dnf.yml` with a comment tying them to the rules. — done.
4. Add `tests/check-cjk-fontconfig.sh`; run it and the full suite. — done (13/13 green).
5. Update `AGENTS.md`; run `doc-contract check --repo-root . --offline`. — done (0 errors, baseline warnings only).
6. Land via `doc-contract`, commit once. — done.

## Verify

- `bash tests/check-cjk-fontconfig.sh` passes, as does `for t in tests/check-*.sh; do bash "$t"; done`.
- `doc-contract check --repo-root . --offline` is green apart from the existing baseline warnings.
- Host, before/after the image lands: `fc-match 'sans-serif:lang=zh-cn'` returns
  `Noto Sans CJK SC`; `zh-tw`, `zh-hk`, `ja`, and `ko` return their TC/HK/JP/KR families;
  `serif` and `monospace` likewise; plain `sans-serif`/`serif`/`monospace` are unchanged.
- Flatpak, after rebase: `flatpak run --command=fc-match com.spotify.Client 'sans-serif:lang=zh-cn'`
  returns `Noto Sans CJK SC`. A machine that already carries the legacy user-level override must
  point it at the same image config, because `--unset-env` unsets rather than falling through to the
  system layer:
  `flatpak override --user --env=FONTCONFIG_FILE=/run/host/fonts/cjk-defaults/flatpak-fonts.conf`.
  The system override can be inspected with `sudo flatpak override --system --show`.
- `/run/host/fonts/cjk-defaults/flatpak-fonts.conf` is readable inside a sandbox; no host
  `/etc`/`/usr` path is granted to Flatpak.
- Invariant spot-check: `files.yml` still runs first, all install modules still precede
  `systemd.yml`, and no `/var/lib/flatpak` content is shipped from the image.

## Out of scope

- User-scoped Flatpak installations: Flatpak intentionally does not apply system-wide overrides to
  apps installed under `~/.local/share/flatpak`.
- Per-user fontconfig overrides (`~/.config/fontconfig`) and the user's existing
  `99-dms-theme-sync.conf`; the host rule uses `prepend_first` to win without rewriting it.
- Removing or modifying the user-installed FangSong/STSong fonts.
- Selecting a non-Noto default; changing the family strings in the shared rules is the follow-up.
