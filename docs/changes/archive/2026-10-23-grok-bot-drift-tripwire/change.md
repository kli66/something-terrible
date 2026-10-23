---
id: grok-bot-drift-tripwire
status: landed
persistence: ephemeral
depends_on:
  - add-grok-bot
files_owned:
  - docs/changes/grok-bot-drift-tripwire/change.md
  - recipes/module-recipes/scripts.yml
  - tests/check-grok-bot-install.sh
  - AGENTS.md
  - docs/layer-optimization.md
accepted_at: 2026-10-23
started_at: 2026-10-23
landed_at: 2026-10-23
archive_path: docs/changes/archive/2026-10-23-grok-bot-drift-tripwire
---
# Fail the build when the Grok Bot stable channel outruns the pin

Status: Landed · 2026-10-23

**Exit reconciliation (2026-10-23).** All four tasks are done. The resolver was re-checked live: it
answers `302` with the pinned 0.75.3 location, and `curl -fsSI` returns the same `Location`, so the
update command in the block comment is accurate. The tripwire logic was exercised three ways
outside the image build: the current artifact behind a different build path passes, a simulated
0.76.0 artifact fails with the stale-pin message, and an unresolvable product id (`404`) takes the
`did not resolve` branch. `bash tests/check-*.sh` is 9/9 green and `doc-contract check --repo-root .
--offline` reports 0 errors / 0 new warnings. `docs/layer-optimization.md` was re-stamped
(`self_hash` 88c64765… → 50b7e897…). The pin remains the only install source: sha256 verification,
RPM identity assertions, the repo disable, and the single `dnf5 clean all` are unchanged.

**Upstream dependencies:** Available: the landed `add-grok-bot` block (0.75.3 pin + committed sha256)
and the vendor's own stable routing endpoint,
`https://api2.cursor.sh/updates/download/stable/linux-x64/grok-bot-cc18e4e726507b90`, which the
`x.ai/bot` page's JS uses. Verified 2026-10-23: it answers `302` with
`Location: https://downloads.cursor.com/grokbot/stable/5acb0be51…/linux/x64/grok-bot-0.75.3-1.x86_64.rpm`
— the same artifact this repository pins. An unknown product id answers `404` and a response without
a redirect leaves `%{redirect_url}` empty, so `curl -fsS` plus a non-empty match fails closed on both.
**Gated:** none.
**Dependents:** None in this repository. This hardens the landed `add-grok-bot` block; nothing else
reads it.
**Files owned:** `docs/changes/grok-bot-drift-tripwire/change.md`,
`recipes/module-recipes/scripts.yml`, `tests/check-grok-bot-install.sh`, `AGENTS.md`, and
`docs/layer-optimization.md`. `AGENTS.md` is also listed by the proposed
`docs/changes/add-skillshare-manager/`; that overlap is soft (different prose regions) and whoever
lands second rebases.

## Why

The pin is deliberate but silent: Grok Bot can ship 0.75.4, and this image keeps installing 0.75.3
with nothing in the build log saying a bump is due. The vendor does expose a stable resolver (the
`api2.cursor.sh` routing endpoint the download page calls, whose `302` target carries the version in
the filename), so the build can ask the channel what it currently advertises and stop when that is no
longer the pinned artifact. That keeps both properties this repository wants: the reviewed pin and
its sha256 anchor stay authoritative, and a stale pin becomes a visible build failure instead of
silent drift.

This is **not** auto-update, and the difference is the point. Installing whatever the resolver returns
would drop the only integrity anchor this unsigned artifact has and let an unreviewed version ride in
whenever the module's cache is invalidated by an unrelated edit. Making the check fail closed also
means a vendor CDN or `api2` outage stops the build; that is accepted deliberately, because the
alternative is a tripwire that silently disappears exactly when it cannot see upstream.

## What changes

### Δ ADDED

- A drift check in the existing Grok Bot block, placed after the host gate and before the 97 MB
  download: a `GROK_BOT_STABLE_URL` constant naming the vendor routing endpoint; resolution with
  `curl -fsS -o /dev/null -w '%{redirect_url}'` captured into a variable with an explicit failure
  branch; a `case` comparing the resolved file name against `${GROK_BOT_URL##*/}` (the pinned file,
  not a second literal); and a failure message naming the advertised URL plus the three constants to
  update (`GROK_BOT_URL`, `GROK_BOT_SHA256`, and the version/date annotation).
- Test coverage for the resolver constant, the `%{redirect_url}` call, both failure messages, the
  ordering (tripwire before download) and the negative that the block never installs the resolved
  URL — the pin stays the only install source.

### Δ MODIFIED

- The Grok Bot block comments: record the resolver, that the version appears only in the redirect,
  and that the tripwire is a review prompt rather than an update mechanism.
- `tests/check-grok-bot-install.sh`: new assertions, no relaxation of the existing ones.
- `AGENTS.md` (`scripts.yml` pattern paragraph) and `docs/layer-optimization.md` (Grok Bot integrity
  sentence), the frozen doc re-stamped with `doc-contract stamp layer-optimization`.

### Δ REMOVED

- Nothing.

## Tasks

1. Add the resolver constant and drift tripwire to the Grok Bot block in
   `recipes/module-recipes/scripts.yml`. — done.
2. Extend `tests/check-grok-bot-install.sh` and run the whole suite. — done (9/9 green).
3. Update `AGENTS.md` and `docs/layer-optimization.md`, then stamp the frozen doc. — done.
4. Run `doc-contract check --repo-root . --offline`, land, and commit once.

## Verify

- `bash tests/check-grok-bot-install.sh` passes and the suite stays 9/9 green.
- `doc-contract check --repo-root . --offline` is green.
- Live re-check at implementation time: the resolver still returns the pinned 0.75.3 artifact, so the
  tripwire's happy path is real and not a permanent failure.
- Negative check: the block installs only `GROK_BOT_URL` (the pin); the resolved URL is compared and
  never downloaded or installed.
- Invariant spot-check: the sha256 verification, RPM identity assertions, repo disable, single
  `dnf5 clean all`, and module order are unchanged.

## Out of scope

- Switching to resolved-latest installs (recorded as intentionally rejected above).
- Any self-update path inside the image, and re-enabling the vendor yum repo.
- Bumping to a newer Grok Bot version; that remains a reviewed change when the tripwire fires.
