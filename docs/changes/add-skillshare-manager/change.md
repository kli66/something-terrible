# Add Skillshare as the image-managed skill service

Status: Proposed (not accepted) · Proposed 2026-08-06

**Upstream dependencies:** Existing BlueBuild recipe ordering in `recipes/recipe.yml` and the `files.yml` -> executable module -> `systemd.yml` installation pattern are available. The canonical upstream is `runkids/skillshare`, which publishes versioned Linux archives, UI bundles, and checksums. Implementation must commit literal expected SHA-256 values for both the executable archive and matching UI bundle, then assert the installed version at image build time.
**Dependents:** None in this repository. Any migration from cc-switch skill management is a separate manual operator action after this image change lands and is not part of this change's acceptance.
**Files owned:** `docs/changes/add-skillshare-manager/change.md`, `recipes/module-recipes/skillshare.yml` (new), `recipes/recipe.yml`, `files/system/usr/lib/systemd/user/skillshare.service` (new), `files/system/usr/libexec/skillshare-prepare-ui` (new), `recipes/module-recipes/systemd.yml`, `tests/check-skillshare-install.sh` (new), `docs/skillshare.md` (new), and the Skillshare architecture/test notes in `AGENTS.md`. User-owned skill stores, agent target directories, cc-switch state, and Skillshare runtime configuration are explicitly not owned.

## Why

The bootc image should provide a dedicated application for managing portable Agent Skills across Pi, Claude Code, and Codex. Skillshare provides a canonical source model, per-target synchronization, source tracking, static security audit, backup/restore, Git synchronization, and a loopback web UI. Installing it through the custom image makes the executable and service lifecycle reproducible across image deployments without coupling it to an unrelated provider-switching tool.

The image should provide the Skillshare executable, matching dashboard assets, and service definition immutably, while all skill content, Git credentials, target selection, UI cache, and operator configuration remain under the user's writable home. The service should be host-native rather than a Quadlet container. Skillshare needs host-valid filesystem paths and may eventually write across several user-owned agent directories; a container would need equivalent broad writable same-path mounts, UID mapping, and SELinux coordination while gaining little isolation. The repository already uses the equivalent host-native BlueBuild module plus user-service pattern for AgentsView.

This change installs the management capability only. It does not migrate, import, relink, reconcile, disable, or delete any existing skill-management state.

## What changes

### Δ ADDED

- Add a BlueBuild `containerfile` module that downloads a pinned `runkids/skillshare` Linux release archive and matching UI bundle, verifies each against a literal expected SHA-256 committed in the module, installs the executable and immutable UI seed, and asserts the expected version during the image build.
- Add `skillshare-prepare-ui`, an idempotent helper that validates the exact pinned cache contents before service start; it atomically seeds an absent cache, atomically reseeds stale/incomplete content, and fails closed on an invalid image seed rather than allowing an unverified runtime asset download.
- Add a packaged `skillshare.service` user unit that runs the global dashboard on `127.0.0.1:19420` with `--no-open`.
- Gate the globally enabled unit on an operator-created `~/.config/skillshare/.image-service-ready` marker so image installation alone cannot start the dashboard or initialize user state.
- Make systemd the sole restart owner. Account for Skillshare's clean foreground exit during dashboard restart, retain `KillMode=control-group`, and apply restart delay/start-rate limits.
- Add an operator guide for first initialization, readiness opt-in, immutable binary/UI upgrades, runtime troubleshooting, and the boundary between Skillshare, APM, native plugin systems, and manual skill migration.
- Add a bash intent test covering literal artifact hashes, version assertion, recipe ordering, loopback-only service, readiness gating, restart ownership, user-session lifecycle, and absence of baked user state.

### Δ MODIFIED

- Insert `skillshare.yml` after `files.yml` and before `systemd.yml` in `recipes/recipe.yml`.
- Enable `skillshare.service` globally in the user scope of `recipes/module-recipes/systemd.yml`; its readiness condition keeps it inactive until the operator explicitly opts in.
- Extend `AGENTS.md` with the Skillshare module, service, and coupled test ownership.

### Δ REMOVED

- None.
- In particular, do not remove or modify cc-switch, existing skill links, existing agent directories, or user-owned skill content.

## Design constraints

1. **Installation is not migration.** Building, deploying, or booting the image must not inspect, import, relink, reconcile, disable, or delete existing skills or cc-switch state.
2. **Immutable executable and UI, mutable user state.** The bootc image owns `/usr/bin/skillshare`, the matching pinned UI seed, helper, and unit. The user home owns Skillshare config, registry, populated UI cache, source checkout, backups, trash, Git state, and all skills.
3. **Image-only upgrades.** Binary and UI versions change only through reviewed recipe pins and a new bootc image. Skillshare self-upgrade is unsupported and must not modify `/usr/bin/skillshare`.
4. **No unattended activation.** Building or rebasing the image must not initialize Skillshare or start the dashboard before the operator creates the readiness marker.
5. **Systemd owns restart.** The dashboard restart path must converge to one systemd-owned `MainPID`; detached helpers must not become an alternate supervisor.
6. **Loopback only.** The dashboard listens on `127.0.0.1:19420`. Remote access requires an explicit operator-controlled SSH tunnel or authenticated proxy; the image does not expose a LAN socket.
7. **Static audit is not a sandbox.** Installing Skillshare does not make third-party skills trustworthy. Source review and host-agent permissions remain separate responsibilities.
8. **No secret or credential baking.** Git tokens, SSH material, remote URLs containing credentials, runtime config, and skill contents remain out of `files/system` and the recipe.
9. **Separate dependency/plugin layers.** Project-level APM manifests and native Pi/Claude/Codex plugin systems remain independent of this global Skillshare application.

## Tasks

1. Select a `runkids/skillshare` release. Record canonical release URLs, expected version, and literal SHA-256 values for the Linux executable archive and matching `skillshare-ui-dist.tar.gz`; do not establish trust by downloading checksums from the same mutable release during every build.
2. Add `recipes/module-recipes/skillshare.yml`; verify both literal hashes, install `/usr/bin/skillshare` and an immutable UI seed under `/usr/share/skillshare`, and assert `skillshare --version` during the build. Couple version, URLs, hashes, and update instructions in one block.
3. Add `files/system/usr/libexec/skillshare-prepare-ui`; validate a present cache against the pinned manifest, atomically seed or reseed the exact expected contents, and fail closed before `ExecStart` when the image seed itself is invalid. The helper must not permit an unverified release-download fallback.
4. Add `files/system/usr/lib/systemd/user/skillshare.service` with `ConditionUser=kai`, `ConditionPathExists=%h/.config/skillshare/.image-service-ready`, graphical-session lifecycle, loopback binding, no browser launch, `KillMode=control-group`, systemd-owned clean-exit restart behavior, restart delay/start-rate limits, and compatible hardening.
5. Add the module in the required recipe order and enable the packaged user unit through `systemd.yml`.
6. Add `tests/check-skillshare-install.sh` and update `AGENTS.md` so literal hashes, version pin, UI seed/helper, module order, service behavior, and user-state exclusions are mechanically coupled.
7. Write `docs/skillshare.md` with installation architecture, initialization and readiness-marker steps, immutable executable/UI upgrade policy, unsupported self-upgrade behavior, health/restart troubleshooting, `systemctl --user reset-failed` recovery, and an explicit statement that migration from any existing manager is manual and out of scope.
8. Build and deploy the image without creating Skillshare configuration or the readiness marker. Verify that the globally enabled unit remains skipped and that no existing user skill path changes.
9. In an isolated temporary home/state tree, use a temporary systemd drop-in or equivalent test harness to redirect the readiness condition and all relevant XDG paths without editing the packaged unit or touching the operator's real marker. Initialize a disposable Skillshare configuration and verify UI-cache preparation, service startup, health, loopback binding, Git access, restart ownership, and self-upgrade behavior without touching real skill stores or agent targets.
10. After runtime acceptance, document the selected version, literal hashes, built-image evidence, and isolated runtime results in this change item and `docs/skillshare.md`. Keep the change item as repository history because this repository has no installed doc-contract archive workflow.

## Verify

- `bash tests/check-skillshare-install.sh` passes.
- All existing `tests/check-*.sh` scripts pass.
- `systemd-analyze --user verify` accepts the installed `skillshare.service` in the built image/test user environment.
- The recipe schema remains valid and CI successfully builds and signs the bootc image.
- The built image contains exactly the pinned Skillshare version and matching hash-pinned UI seed, with no Skillshare config, skills, credentials, backups, registry, trash, or populated user cache.
- A deployment with no readiness marker leaves `skillshare.service` skipped and causes no changes under existing user skill stores or agent target directories.
- With an isolated temporary home/state tree and test-only systemd path redirection, the readiness marker starts the packaged unit successfully; invalid/incomplete configuration is bounded by restart delay/start-rate limits and fails visibly without mutating agent targets.
- `curl --fail http://127.0.0.1:19420/api/health` succeeds during the isolated runtime test; socket inspection shows no non-loopback listener for port 19420.
- Dashboard restart leaves exactly one active server owned by `skillshare.service`, with the new process reported as systemd's `MainPID` and no detached helper remaining.
- Removing or corrupting the isolated populated UI cache is detected before service start and recovered atomically from the image-pinned seed without a network download; a corrupt image seed fails closed, and network observation or blocking confirms no release-asset fallback was attempted.
- Git fetch/check operations work from the isolated service environment without baking credentials or broadening the unit beyond required home/network access.
- Skillshare binary self-upgrade is unavailable or fails without changing `/usr/bin/skillshare`; version changes occur only through a new image pin and deployment.
- Invariant spot-check: module order remains `files.yml` before executable-copy modules and all such modules before `systemd.yml`; image builds remain documentation-change-skipping, CI-owned, signed, and free of user secrets.

## Out of scope

- Migrating away from cc-switch skill management.
- Importing, copying, moving, deleting, or relinking any existing skill.
- Changing `~/.cc-switch/skills`, `~/.pi/agent/skills`, `~/.claude/skills`, `~/.codex/skills`, or `~/.agents/skills`.
- Configuring production Skillshare targets, filters, Git remotes, or canonical skill storage.
- Replacing or modifying cc-switch provider switching.
- Managing Pi extensions/packages, Claude plugins/hooks, Codex plugins/connectors, or agent credentials through Skillshare.
- Deploying Microsoft APM globally or generating project `apm.yml` files.
- Exposing Skillshare outside loopback.
- Automatic installation, update, or activation of public marketplace results.
- Adding a Skillshare Quadlet or a general-purpose container-management framework for user services.
