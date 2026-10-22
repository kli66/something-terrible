---
persistence: living
---

# AGENTS.md — how to work in this repo (the operating contract)

The durable operating contract for any agent touching this repo, followed by this image's
project-specific guidance. The stdlib-only `doc-contract` CLI reads `.doc-contract.toml` and keeps
the mechanically checkable parts of this contract honest.

## The doc taxonomy (where each kind of doc lives)

```
AGENTS.md                        this file — the operating contract + change/handoff protocol (living)
.doc-contract.toml               canonical resolver configuration (the only config input)
docs/
  roadmap.md                     cross-change order; edges owned by change front-matter, rendered here (living)
  changes/                       substantial in-flight work (propose → accept → begin → land → archive)
    <name>/change.md             default: a single change file (split only if genuinely large)
    archive/<date>-<name>/       landed changes (lineage)
  hardware-notes.md              frozen reference — target-hardware diagnostics
  layer-optimization.md          frozen reference — layer/pinning policy analysis
  self-build-todo.md             deferred register — trigger-gated backlog, struck on promotion
  superseded/                    non-Markdown lineage artifacts (not resolver nodes)
HANDOFF-*.md                     ephemeral scaffolding for a next agent, never the durable home for open work
```

There is no `docs/adr/` or `docs/spec/` tier yet, and no project capability check
(`[capability] mode = "skip"` in `.doc-contract.toml`). If a decision ever needs a frozen WHY record,
add `docs/adr/` and declare it; do not smuggle decisions into the roadmap prose.

**Every managed doc carries a `persistence:` header and is a node in the change-DAG resolver** — so
none sits unclassified. That includes `AGENTS.md`, `docs/roadmap.md`, the flat docs named above, and
every change file. They are enumerated in `.doc-contract.toml` `root_nodes`; roots are required by
default and only IDs listed in `optional_roots` may be absent. Frozen docs additionally carry a
`self_hash`, refreshed with `doc-contract stamp <node-id>` after a reviewed edit.

The same discovery result bounds value-free secret scanning: declared roots, selected change files,
and companion Markdown inside selected change folders are scanned. Recipe YAML, `files/`, scripts,
dependency trees, and untracked files are not scanned merely because they exist below the repository
root — use a dedicated security tool for repository-wide secret detection.

## What makes this cheap

Every doc carries four attributes; the maintenance model falls out of them:

1. **Question** — exactly one.
2. **Persistence** — `frozen` (hardware notes, layer analysis, archive — append-only, `self_hash`-guarded) ·
   `living` (this file, `docs/roadmap.md` — the *only* docs kept true by hand) · `ephemeral`
   (`docs/changes/` folders, handoffs — cost is *disposal* on land) · `deferred`
   (`docs/self-build-todo.md` — low-upkeep, entries struck on promotion).
3. **Canonical owner** — single source for its fact; never maintained in two places.
4. **Forcing function** — what drags the doc back to true. `frozen` → none. `ephemeral` →
   delete-on-land. `living` → the change-protocol reconciliation (roadmap refreshed on every change
   entry/exit) or a tripwire test. `deferred` → a **per-entry Trigger**.

There is no "review cadence." The living set is deliberately small: the roadmap's edges are a
function of change front-matter (enforced by `doc-contract check`), while the prose stays
human-judged. The recipe has its own tripwires — `tests/check-*.sh` — but those guard the *image*,
not these docs.

## Deferred register — `docs/self-build-todo.md`

Forward-looking, trigger-gated work lives there: not a decision, not in-flight, not tripwire-testable.
Each entry names its **Trigger**. When a trigger fires, promote the entry to a `docs/changes/<name>/`
folder, strike it from the register, and add it to the roadmap.

## Change weight — scale ceremony to the work

- **Trivial edit** → a `docs/roadmap.md` line + commit. No folder.
- **Substantial work** → a `docs/changes/<name>/` folder, default a **single `change.md`**
  (`## Why` · `## What changes` [Δ ADDED/MODIFIED/REMOVED] · `## Tasks` · `## Verify`).
- **Rare meta-change** → split into `proposal.md` / `design.md` / `tasks.md`, only when each section
  is genuinely large. Three files is the *ceiling*, not the default.

## Change / handoff protocol (MANDATORY)

Substantial open work lives in a `docs/changes/<name>/` folder — **not** in a root `HANDOFF-*.md`.
A `HANDOFF-*.md` is ephemeral scaffolding for the next agent, never the durable home for open work.

Each change file opens with YAML front-matter — the **canonical owner of order and status**:

```yaml
---
id: <folder-name>
status: proposed      # proposed | accepted | in-progress | blocked | landed
persistence: ephemeral
depends_on: []        # upstream change ids, one direction only; dependents are computed
files_owned: []       # exact repo-relative paths this change may write
---
```

**On entry, before touching anything:**

1. Run `doc-contract reconcile mechanical docs/changes/<name> --phase entry --format json
   --repo-root .`, then judge the change's claims against the roadmap and the repo: do task IDs,
   file paths, and status claims still match? Mechanical readiness never replaces that judgment.
2. If material drift has occurred, repair the change or the roadmap first, then rerun. If a change's
   detail contradicts a decision record, **stop and surface it** rather than editing the two to match.
3. Only after a green report and that judgment: `doc-contract begin docs/changes/<name> --repo-root .`.

**On exit, before finishing:**

1. Run `doc-contract reconcile mechanical docs/changes/<name> --phase exit --format json --repo-root .`.
2. Reconcile semantic claims: tasks actually done, `Verify` evidence recorded, durable findings moved
   into the frozen/living docs, roadmap narrative still true. Repair, then rerun.
3. `doc-contract land docs/changes/<name> --repo-root . --dry-run` (add `--diff` when line-level
   review is wanted), then the reviewed command without `--dry-run`. Landing owns the status edit,
   roadmap regeneration, fingerprint refresh, journal, and the move to
   `docs/changes/archive/<date>-<name>/`. Never hand-roll those.

**Dependency-chain rule.** Front-matter `depends_on` is the canonical owner of order; the CLI resolves
it into the DAG (topo-sort + cycle/dangling/overlap/linkage checks) and renders the Mermaid block in
`docs/roadmap.md`. The roadmap prose carries rationale and one line per change, not the edges.
Linkage is checked: an active change must have a roadmap line naming its folder with a status token.

**Hashing policy.** `edge_fingerprints = "advisory"` here: an absent edge hash is accepted, while an
explicit empty, `PENDING`, malformed, or stale value warns. Frozen `self_hash` validation is always
strict (append-only). Both hash the canonical body: front matter, line endings, per-line trailing
whitespace, and boundary blank lines are normalized; prose reflow and Markdown rewrites are
significant. `doc-contract stamp` owns refreshing them.

## Executing a change → dispatch is one line

The entry/exit steps are standing protocol, so a dispatch never restates them. Once this contract is
loaded, dispatch collapses to: **"Execute `docs/changes/<name>/`."** That authorizes implementation,
verification, transactional landing, and exactly one final commit unless the dispatch says otherwise.
Before dispatch, only an explicit user or reviewer instruction authorizes `doc-contract accept`.

The final commit uses a Conventional Commits header limited to 50 characters, body lines wrapped at
72, and a concise body under 100 words (omit it when the header suffices).

## Project: what this is

A [BlueBuild](https://blue-build.org/) recipe that builds a personal, signed Fedora **Kinoite 44** (atomic/ostree) OS image, published to `ghcr.io/kli66/something-terrible`. There is no application code — the "source" is declarative YAML describing packages, fonts, files, kernel args, and systemd state baked into the image at build time. The desktop is a **niri** (Wayland) + KDE-portal setup with `greetd`/`tuigreet` login and `fcitx5`/rime input.

## Build & test

- **Building is done by CI, not locally.** Every push (except `**.md`-only changes) triggers `.github/workflows/build.yml`, which delegates the entire build to the `blue-build/github-action`. Pushing is the build.
- **Local image build** (only if BlueBuild CLI is installed): `bluebuild build ./recipes/recipe.yml`. Most edits are validated faster by reading the schema and running the tests below.
- **Tests** are plain bash assertions that grep the recipe YAML — they verify *intent* (a package/snippet is present and ordered correctly), not a built image. Run the whole suite (8 files):
  ```bash
  for t in tests/check-*.sh; do bash "$t"; done
  ```
  (e.g. `tests/check-bettbox-install.sh`, `tests/check-bitwarden-install.sh` — one per vendored/systemd feature). When you change install logic in `scripts.yml`/`systemd.yml`, update or add a matching `tests/check-*.sh` and run it.
- **Docs gate**: `doc-contract check --repo-root . --offline` must stay green alongside the suite.

## Architecture

`recipes/recipe.yml` is the entrypoint. It sets `base-image`/`image-version` and pulls in ordered module files via `from-file`. **Module order matters** — modules run top-to-bottom during the build, and a test enforces that `scripts.yml` runs before `systemd.yml`. The `signing` module (cosign/Sigstore) is last.

Each `recipes/module-recipes/*.yml` is one BlueBuild module:

- **`dnf.yml`** — RPMs from Fedora, RPMFusion (`nonfree`), and COPR (`scottames/ghostty`, `avengemedia/dms`). `group-install` pulls `@multimedia` + `@development-tools`. The `exclude` list (e.g. `alacritty`, `waybar`, `fuzzel`) actively *removes* packages. This is the canonical place for repo-available packages.
- **`scripts.yml`** — escape hatch for software **not** in any repo. Each snippet runs `set -oue pipefail` and uses `dnf5 install`. Patterns in use, each (except the terra-repo block) with its coupled `tests/check-*.sh`: pinned GitHub release RPM URLs (Bettbox, CC Switch, Chipmunk; `tests/check-bettbox-install.sh`) with a version/date annotation comment next to each URL — the layers cache and only change on a deliberate bump; a vendor redirect URL (Bitwarden; `tests/check-bitwarden-install.sh`); a vendor JSON manifest + checksum-verified download (Proton Pass; `tests/check-proton-pass-install.sh`) — resolve the newest entry from the vendor manifest, select the platform artifact, verify the checksum that same manifest names, install, then assert the result against the resolved version held in a shell variable rather than a second literal, because the manifest and the artifact share an origin, so that hash catches corruption/truncation/retargeting but is not a signature; and the terra-repo block, which enables the repo, installs, then disables it again so it doesn't persist in the image — it has no test file of its own and is asserted from `tests/check-dms-install.sh` and `tests/check-proton-pass-install.sh`. When bumping a pin, update the RPM URL and its version/date annotation comment together.
- **`files.yml`** — copies `files/system/` onto the image root (`/`). So `files/system/etc/greetd/config.toml` lands at `/etc/greetd/config.toml`. Add baked-in config here.
- **`systemd.yml`** — declares `enabled`/`disabled`/`masked` units (e.g. enables `greetd`, disables `plasmalogin`, masks `systemd-remount-fs` to avoid a known Atomic 42+ boot failure).
- **`fonts.yml`** — nerd-fonts + google-fonts (heavy CJK Noto coverage).
- **`kargs.yml`** — kernel arguments (btrfs zstd compression, `noatime`; amdgpu PSR/DMUB suspend-freeze workaround). Before adding or changing a karg, check `docs/hardware-notes.md` — it has target-hardware diagnostics and general rpm-ostree kargs persistence/stability caveats.
- **`brew.yml`** — enables Homebrew on the image.

`files/scripts/example.sh` is upstream template boilerplate, not wired into the build.

## Conventions

- **Add a package the right layer:** in a repo → `dnf.yml` `install`; needs a third-party repo/RPM URL → a snippet in `scripts.yml`; a config file → `files/system/...` via `files.yml`; a service toggle → `systemd.yml`.
- When asked to add a package while running from a Fedora Linux system, first verify local Fedora repository availability with `dnf5 search <package>` or `dnf5 repoquery --info <package> --cacheonly` before deciding whether it belongs in `dnf.yml` or `scripts.yml`.
- **In `scripts.yml`**, always: install with `dnf5`, clean up temp files, and leave any temporarily-enabled repo disabled. End the module with `dnf5 clean all`. The RPM URLs are pinned constants (nothing is resolved at build time) only for the GitHub release pins; the vendor-redirect and vendor-manifest blocks resolve latest whenever that layer re-executes. Either way, verify that a new URL resolves when bumping, and keep each URL and its version/date annotation comment in sync — for a resolved-latest block, refresh its `Last validated <date>` annotation when the resolution is re-checked, where it has one (the Proton Pass block does; add one when next touching the Bitwarden block).
- **The image is the README's identity** — `README.md` is still largely the upstream BlueBuild template; don't treat it as authoritative about this specific image.
- Comments in the YAML explain *why* (workarounds, bug links). Preserve them when editing nearby lines.
