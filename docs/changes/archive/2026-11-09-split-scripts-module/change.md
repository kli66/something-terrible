---
id: split-scripts-module
status: landed
persistence: ephemeral
depends_on:
files_owned:
  - docs/changes/split-scripts-module/change.md
  - recipes/recipe.yml
  - recipes/module-recipes/bettbox.yml
  - recipes/module-recipes/bitwarden.yml
  - recipes/module-recipes/cc-switch.yml
  - recipes/module-recipes/chipmunk.yml
  - recipes/module-recipes/grok-bot.yml
  - recipes/module-recipes/proton-pass.yml
  - recipes/module-recipes/terra.yml
  - tests/check-bettbox-install.sh
  - tests/check-bitwarden-install.sh
  - tests/check-cc-switch-install.sh
  - tests/check-chipmunk-install.sh
  - tests/check-dms-install.sh
  - tests/check-grok-bot-install.sh
  - tests/check-proton-pass-install.sh
  - AGENTS.md
  - docs/layer-optimization.md
accepted_at: 2026-11-09
started_at: 2026-11-09
landed_at: 2026-11-09
archive_path: docs/changes/archive/2026-11-09-split-scripts-module
---
# Split the vendored-app script module

Status: Landed · 2026-11-09

## Why

`recipes/module-recipes/scripts.yml` is one 252-line `script` module that installs seven
independent things: Bettbox, CC Switch, Bitwarden, Chipmunk, Grok Bot, Proton Pass, and the
terra-repo packages (`nwg-look`, `zed`). It is the only module that bundles unrelated install
features, and that bundling has three costs:

1. **Cache coupling.** All snippets in a `script` module run in one layer. Bumping one vendor
   re-executes the whole layer, re-downloading every other vendor artifact; Proton Pass alone is
   ~177 MB downloaded and ~447 MB installed per re-execution. Per-vendor modules let a bump
   invalidate only that vendor's layer.
2. **Test coupling.** The Grok Bot and Proton Pass tests re-derive their block with `sed`/`awk`
   ranges inside the shared file, assert sibling-block order that nothing depends on, and carry
   "no asserts about other vendors" caveats. Each test should scope to one file.
3. **Review surface.** A change to one vendor's trust anchor is reviewed inside a file that also
   holds six other trust anchors, each with its own comment block.

`dnf.yml` stays whole: it is the single canonical place for repo-available packages, and its
repo/group/package sections are one install feature. `systemd.yml`, `files.yml`, `fonts.yml`,
`kargs.yml`, `brew.yml`, and `agentsview.yml` already hold one feature each.

## What changes

### Δ ADDED

- `bettbox.yml`, `bitwarden.yml`, `cc-switch.yml`, `chipmunk.yml`, `grok-bot.yml`,
  `proton-pass.yml`, `terra.yml` — one `script` module per vendored install, each with its own
  `set -oue pipefail`, its original comments and assertions verbatim, and its own
  `dnf5 clean all` tail.
- `tests/check-cc-switch-install.sh` and `tests/check-chipmunk-install.sh`, closing the two
  vendored blocks that previously had no test of their own.
- This change file.

### Δ MODIFIED

- `recipes/recipe.yml`: replace the single `scripts.yml` entry with one entry per new module.
  `terra.yml` stays after `dnf.yml` (its `quickshell-git` prerequisite); every vendored module
  stays before `agentsview.yml`/`systemd.yml`.
- `tests/check-{bettbox,bitwarden,grok-bot,proton-pass}-install.sh`: point at the per-vendor
  file; drop cross-block ordering and "shared file" scoping machinery that no longer exists.
  The Grok Bot and Proton Pass trust-boundary assertions are unchanged.
- `tests/check-dms-install.sh`: assert `dnf.yml` before `terra.yml`; carry the terra-block
  assertions that used to live in the Proton Pass test; scan every module file for a
  comment-stripped `noctalia-shell` regression.
- `AGENTS.md`: replace the `scripts.yml` architecture and conventions text with the per-vendor
  module layout; update the test inventory from 10 to 12 files.
- `docs/layer-optimization.md`: append a dated note recording the split, its cache rationale,
  and the six extra layers; refresh the frozen `self_hash` with `doc-contract stamp`.

### Δ REMOVED

- `recipes/module-recipes/scripts.yml` (every block moves to its own module).

## Tasks

1. Create the seven per-vendor modules with the existing snippets moved verbatim, each with
   `set -oue pipefail` and a `dnf5 clean all` tail.
2. Replace the `scripts.yml` entry in `recipe.yml` with the seven module entries in dependency
   order.
3. Delete `scripts.yml`.
4. Update the four existing coupled tests, add the two missing ones, and update the DMS test's
   terra/ordering scope.
5. Update `AGENTS.md`; append the layer-optimization note and stamp the frozen doc.
6. Run the whole suite and `doc-contract check --repo-root . --offline`.

## Verify

- `for t in tests/check-*.sh; do bash "$t"; done` — all 12 pass.
- `doc-contract check --repo-root . --offline` — 0 errors; warnings are the five pre-existing
  skillshare ones. (`recipes/module-recipes/scripts.yml` is deleted by this change and therefore
  must not sit in `files_owned`, which the resolver requires to exist.)
- No file in `recipes/`, `tests/`, or `AGENTS.md` references `module-recipes/scripts.yml`.
- Every `recipe.yml` `from-file` target exists; `signing` is last; `dnf.yml` precedes `terra.yml`;
  all install modules precede `systemd.yml`.
- `bash -n` passes on every test script; all 15 module/recipe YAML files parse.

### Evidence

- 12/12 tests pass after the split; the two new tests (`check-cc-switch-install.sh`,
  `check-chipmunk-install.sh`) pass on the first run.
- YAML parsed with Bun's YAML parser (no PyYAML in the build environment): 15/15 files valid under
  both `modules:`-wrapped and bare-module `from-file` shapes.
- URL re-check while touching the Bitwarden module: the redirect resolves to
  `Bitwarden-2026.10.4-x86_64.rpm`; the pinned Bettbox, CC Switch, and Chipmunk assets return 200.
- BlueBuild itself was not run locally (CI owns the build); this change adds no new package or
  command, only a layer split.

## Out of scope

- Splitting `dnf.yml`, `systemd.yml`, or `files.yml`.
- Changing any vendor version pin, trust anchor, or install command.
- Making the image build locally; CI owns the build and signature.
- Baking Tern into the image; its builds are private (`build.stencil.so` returns 401 and
  `/api/products` reports `public: false`). That finding lives in `docs/self-build-todo.md`.
