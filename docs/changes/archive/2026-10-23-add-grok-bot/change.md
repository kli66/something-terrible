---
id: add-grok-bot
status: landed
persistence: ephemeral
depends_on:
files_owned:
  - docs/changes/add-grok-bot/change.md
  - recipes/module-recipes/scripts.yml
  - tests/check-grok-bot-install.sh
  - AGENTS.md
  - docs/layer-optimization.md
accepted_at: 2026-10-23
started_at: 2026-10-23
landed_at: 2026-10-23
archive_path: docs/changes/archive/2026-10-23-add-grok-bot
---
# Install Grok Bot from the pinned vendor RPM

Status: Landed · 2026-10-23

**Exit reconciliation (2026-10-23).** All four tasks are done. The pin was re-checked against the
live URL at implementation time: HTTP 200, 97,608,661 B, `last-modified 2026-10-22 19:48:29 GMT`,
`sha256 171c38d0…2cfe9a8`, and the downloaded artifact reports `grok-bot 0.75.3-1 x86_64` from
`rpm -qp`. `bash tests/check-*.sh` is 9/9 green and `doc-contract check --repo-root . --offline`
reports 0 errors / 0 new warnings (the 5 baseline warnings belong to the unrelated proposed
`add-skillshare-manager`). `docs/layer-optimization.md` was edited and re-stamped
(`self_hash` 10e74b2c… → 88c64765…); `AGENTS.md` now says 9 test files and lists Grok Bot in the
`scripts.yml` pattern paragraph. The vendor yum repo still lags the download page at 0.75.2, so the
signed-channel migration stays recorded here as a future option rather than being silently adopted.

**Upstream dependencies:** Available: `https://x.ai/bot`'s Linux download, served as
`https://downloads.cursor.com/grokbot/stable/<build>/linux/x64/grok-bot-<version>-1.x86_64.rpm`
(checked 2026-10-23: HTTP 200, 97,608,661 B, `last-modified 2026-10-22 19:48:29 GMT`, package
`grok-bot 0.75.3-1 x86_64`); the Fedora build container's `dnf5`, `rpm`, `curl`, and `sha256sum`; and
the existing single-snippet `scripts.yml` install pattern. **Gated:** none. The vendor also runs a
signed yum repo at `https://downloads.cursor.com/yumrepo/grok-bot` (`repo_gpgcheck=1`, key
`https://downloads.cursor.com/keys/anysphere.asc`), but it lags the download page — its `repomd`
revision of 2026-10-22T19:41Z lists only up to 0.75.2, four minutes older than the 0.75.3 build — so
it is recorded here as a future option and not used by this change.
**Dependents:** None in this repository. No roadmap item and no other change folder waits on Grok
Bot, and no other change owns the same non-doc paths.
**Files owned:** `docs/changes/add-grok-bot/change.md`, `recipes/module-recipes/scripts.yml`,
`tests/check-grok-bot-install.sh` (new), `AGENTS.md`, and `docs/layer-optimization.md`. `AGENTS.md`
is also listed by the proposed `docs/changes/add-skillshare-manager/`; that overlap is soft
(different prose regions, no shared symbol) and whoever lands second rebases. User-owned state
(`~/.config/Grok Bot`, keyrings, sign-in/session state) is explicitly not owned.

## Why

Grok Bot is a vendor desktop agent with no Fedora, RPM Fusion, or COPR package, so `dnf.yml` has
nothing to install; `scripts.yml` is the documented escape hatch and already carries the same shape
for Bettbox, CC Switch, Chipmunk, and Proton Pass. `x.ai/bot` exposes the Linux artifact only as a
build-specific URL (`grokbot/stable/<build>/linux/x64/…`): there is no version manifest, no checksum
file, and no directory listing (the prefix answers 403). The page's static payload names only the
macOS build, and its Linux link comes from the client-side "More downloads" dialog, so a build cannot
resolve "latest" by scraping it without also lifting Cloudflare's UA gate. The URL is therefore
pinned, exactly like the GitHub-release pins already in this file.

The pin is 0.75.3, the newest stable on the download page at proposal time (the signed yum repo is
one patch behind at 0.75.2). Integrity is deliberately weaker than a signed package and is stated so
rather than implied: the download-page RPM carries **no OpenPGP signature** (`rpm -Kv` reports only
header/payload digests; `%{SIGPGP}` and `%{RSAHEADER}` are both empty), while the yum repo's RPMs are
signed with key ID `42a1772e62e492d6`. A committed `sha256` literal is therefore this block's
integrity anchor: it catches a truncated download, a corrupted CDN object, or a retargeted URL as a
build failure instead of an install, but it does **not** defend against a compromised release
process, because it shares an origin with the artifact. The stronger signed channel is a one-line
migration later (enable the repo, import its key, install by name) once it catches up with the
download page; that trade is recorded here so nobody mistakes the hash for a signature.

Two vendor scriptlet behaviours shape the block. The `%post` registers
`/etc/yum.repos.d/grok-bot.repo` (enabled, `gpgcheck=1`, `repo_gpgcheck=1`, `skip_if_unavailable=1`)
even when the RPM is installed from a local file; on this atomic image `/usr` is immutable, so that
repo can never serve an in-place update, and this change disables it the same way the terra block is
disabled — the vendor's own `grok_bot_repo_enabled()` helper reads an existing `enabled=0` and
preserves it, so the disable survives later upgrades. The `%post` also flips
`/opt/Grok Bot/chrome-sandbox` to 4755 when the installing host lacks unprivileged user namespaces
and leaves it 0755 otherwise; that is the vendor's Electron sandbox decision and this change neither
reimplements nor overrides it (Bettbox already sets its own setuid bit; Proton Pass asserts the
opposite for its own sandbox, so neither posture is a repository-wide rule).

## What changes

### Δ ADDED

- A pinned Grok Bot install block in the existing `recipes/module-recipes/scripts.yml` snippet,
  placed after the Chipmunk block and before the Proton Pass block, so the pinned vendor-URL blocks
  stay grouped and the single final `dnf5 clean all` remains last. The block:
  - pins `GROK_BOT_URL` (build-specific download URL) and `GROK_BOT_SHA256` (the artifact hash),
    with the version/date annotation comment the pinned blocks use, including the update recipe
    (open `x.ai/bot`, take the Linux RPM link from "More downloads", recompute `sha256sum`);
  - downloads to `/tmp`, asserts the file is non-empty, verifies the pinned sha256 with an explicit
    failure branch, and asserts `%{NAME}`/`%{ARCH}`/`%{VERSION}-%{RELEASE}` are
    `grok-bot`/`x86_64`/`0.75.3-1` before installing, so a renamed or retargeted artifact fails the
    build;
  - installs with `dnf5 install -y` and removes the temporary RPM;
  - disables the scriptlet-registered `/etc/yum.repos.d/grok-bot.repo` with the terra-style
    `sed` line, because the image is immutable and the repo is not an update path here;
  - asserts the installed result: `/usr/bin/grok-bot` is executable (the scriptlet reaches it
    through `update-alternatives` or a symlink to `/opt/Grok Bot/grok-bot`), the desktop entry
    exists, and the repo file is present with `enabled=0`;
  - records the non-actions with reasons: no `chmod` on `chrome-sandbox`, no `--no-sandbox`, no
    vendor script execution, no `/usr/local` writes.
- `tests/check-grok-bot-install.sh`, coupling the pin (URL, sha256, version), the hash-failure
  branch, the host gate, the dnf5 install/cleanup lines, the repo disable, and the negative
  assertions (no scraping, no flatpak/snap, no `--no-sandbox`, no sandbox chmod).

### Δ MODIFIED

- `AGENTS.md`: the test count (8 → 9), and the `scripts.yml` pattern paragraph gains Grok Bot as a
  second pinned download-page example with its coupled test.
- `docs/layer-optimization.md` (frozen): the pinned-URL list gains Grok Bot, stamped with
  `doc-contract stamp` after review.

### Δ REMOVED

- Nothing.

## Tasks

1. Add the pinned Grok Bot block to `recipes/module-recipes/scripts.yml` as described above. — done.
2. Add `tests/check-grok-bot-install.sh` and run it plus the whole suite. — done (9/9 green).
3. Update `AGENTS.md` (test count, `scripts.yml` patterns) and `docs/layer-optimization.md`
   (pinned channels), then `doc-contract stamp layer-optimization`. — done.
4. Run `doc-contract check --repo-root . --offline`, land the change, and commit once.

## Verify

- `bash tests/check-grok-bot-install.sh` passes, as does the whole `tests/check-*.sh` suite.
- `doc-contract check --repo-root . --offline` is green.
- The pinned URL still serves 0.75.3 with the committed sha256 (re-download and `sha256sum` checked
  at implementation time), so the pin is not a guess.
- Invariant spot-check: module order is unchanged (`scripts.yml` before `systemd.yml`), the snippet
  still ends with exactly one `dnf5 clean all`, and the earlier pinned blocks, terra enable/disable,
  and Proton Pass assertions are untouched.

## Out of scope

- Enabling the signed vendor yum repo as the install/update channel (recorded above as a migration
  option, gated on it catching up with the download page).
- Sign-in, account state, settings, keyrings, or any other `$HOME` content for Grok Bot.
- Icons, desktop-entry overrides, niri/DMS window rules, and tray integration; the vendor's packaged
  desktop entry is installed as shipped.
