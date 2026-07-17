# Hardware notes — target machine (Lenovo 21J3CTO1WW)

Durable, self-contained diagnostic knowledge about the physical machine this image is
deployed to. Distinct from `AGENTS.md` (which covers this repo's own build conventions) —
this file is about the hardware/kernel behavior a future agent would otherwise have to
re-derive from scratch.

## AMD amdgpu PSR/DMUB suspend freeze

**Status as of 2026-07-12: root-caused, fix applied in `recipes/module-recipes/kargs.yml`
(`amdgpu.dcdebugmask=0x10`). Not yet verified against a rebuilt/deployed image.**

- **Hardware:** Lenovo 21J3CTO1WW, AMD Ryzen "Phoenix1" APU (`lspci` id `1002:15bf`,
  `amdgpu` driver), BIOS `R29ET65W` (1.39, 2026-03-25).
- **Symptom:** the system appears to freeze — sometimes for tens of minutes, sometimes
  permanently (requires a hard reset) — around suspend/resume or logout/login, especially
  after several rapid consecutive suspends.
- **Root cause (confirmed via a captured kernel stack trace, kernel `7.1.3-200.fc44.x86_64`):**
  a `WARNING` fires at `dmub_psr_enable+0x116/0x120` (`drivers/gpu/drm/amd/amdgpu/../display/dc/dce/dmub_psr.c:223`),
  reached via
  `amdgpu_device_suspend → amdgpu_device_ip_suspend_phase1 → amdgpu_ip_block_suspend → dm_suspend
  → drm_atomic_helper_suspend → drm_atomic_helper_disable_all → drm_atomic_commit
  → drm_atomic_helper_commit → commit_tail → amdgpu_dm_atomic_commit_tail
  → amdgpu_dm_commit_streams → dc_set_psr_allow_active → edp_set_psr_allow_active
  → dmub_psr_enable`.
  This is a DMUB (Display Micro-controller Unit) firmware command timeout inside AMD's
  Display Core PSR (Panel Self Refresh) enable path, hit while suspend tries to disable all
  CRTCs. Some codepaths hit a timeout and WARN (recoverable, but stalls for a long time —
  one observed instance blocked suspend for 23 minutes before self-recovering); at least one
  adjacent codepath appears to hang indefinitely with no timeout guard (the unrecoverable
  freeze case) — consistent with no softlockup/NMI/hung-task warning ever firing for that
  case, since the kernel scheduler itself isn't stuck, only the display pipeline is.
- **Trigger:** rapid repeated suspend/resume cycling (observed: 6 cycles in ~3.5 minutes
  produced the captured trace). Not specific to any particular Wayland compositor or shell —
  the same signature (33 self-recovering hits in one boot) was also present under a prior
  noctalia-based setup, before this image switched to niri + DMS. Confirms this is an
  amdgpu/DMUB firmware-handshake bug, not something introduced by this repo's shell choice.
- **Not yet reported upstream** as of 2026-07-12. This exact trace (file/line, full call
  chain, exact hardware/kernel/BIOS versions) is a much stronger report than the
  superficially-similar `niri-wm/niri#2896`, which is DRM-permission-denied noise from the
  same underlying race, not this bug specifically. Worth filing against
  `gitlab.freedesktop.org/drm/amd` if it recurs.
- **Fix, applied to `recipes/module-recipes/kargs.yml`:** kernel
  argument `amdgpu.dcdebugmask=0x10`. Verified directly against the `DC_DEBUG_MASK` enum in
  `drivers/gpu/drm/amd/include/amd_shared.h` at kernel tag `v7.1` (matches the installed
  `kernel-7.1.3-200.fc44`): bit `0x10` = `DC_DISABLE_PSR`, which disables "Panel self refresh
  v1 and PSR-SU" only — no other bits set, no other DC behavior touched. Trade-off: PSR is a
  laptop power-saving feature (lets the eDP panel self-refresh from its own buffer during
  static frames so the GPU can idle); disabling it costs marginally higher idle power
  draw/heat on battery, with no other functional or visual downside.
- **Before applying:** re-diff `amd_shared.h` at whatever kernel tag is current at apply
  time (see the "not ABI-stable" caveat below) — the `0x10` value above was verified against
  the tag matching kernel `7.1.3`, not guaranteed for a later kernel bump.

## Bluetooth headset disconnect → shell crash (why the shell is DMS, not noctalia)

**Status: resolved by switching the shell to DankMaterialShell (DMS) on upstream
quickshell-git; merged to `main` 2026-07-16.** Kept here because it's stack-level
diagnostic knowledge a future agent would otherwise re-derive from coredumps.

- **Symptom:** the desktop shell crashed reproducibly on *abnormal* Bluetooth headset
  disconnect — e.g. plugging a still-connected headset in to charge without disconnecting
  BT first. 5 coredumps in one week, identical signature every time.
- **Crash signature** (same function offsets across all dumps):
  `QObject::disconnect(...)` (blanket 4-arg disconnect on a dead node)
  ← `qs::service::pipewire::PwDefaultTracker::setDefaultConfiguredSink(PwNode*)`
  ← `qs::service::pipewire::PwConnection::onFatalError()` → SIGSEGV.
- **Trigger chain (journal):** headset link drops abnormally
  (`bluetoothd: ext_io_disconnected ... Transport endpoint is not connected (107)`) →
  PipeWire node `bluez_output.*` goes `running -> error` → quickshell treats it as a fatal
  connection error → `onFatalError()` resets the default sink → blanket `QObject::disconnect`
  on a node whose destroy-handler was already torn down.
- **Root cause = quickshell version, not noctalia config.** The old shell ran on
  **noctalia-qs** — a quickshell *fork* frozen on a ~Jan–Mar 2026 snapshot (rev `fb0cc155`,
  RPM version `0.0.12`, which is noctalia's own counter, not a quickshell version). It carried
  the 2026-01-08 reconnect patch that *introduced* the bug but not the fix. Upstream fix =
  quickshell commit `13fe9b0` (2026-04-06, *"services/pipewire: avoid blanket disconnect for
  default nodes"*), shipped in quickshell ≥ 0.3.0 (tagged 2026-05-04).
- **Why not just run noctalia on fixed quickshell:** noctalia forked quickshell specifically
  to add `Quickshell.Niri` (+ `Quickshell.DWL`) modules that upstream ships in *no* release;
  `noctalia-shell` imports `Quickshell.Niri` to read niri workspaces and hard-requires
  `noctalia-qs`, so it won't start on stock quickshell. DMS instead talks to niri over its IPC
  socket directly, so it runs on upstream `quickshell-git`. Hence: switch shells, don't swap
  the binary. (This is also why `noctalia-shell`/`noctalia-qs` must never be reintroduced —
  they Provide+Conflict `quickshell` and would break the DMS install; the recipe files and
  `tests/check-dms-install.sh` guard against it.)
- **Verify after any quickshell bump:** `quickshell --version` reports upstream ≥ 0.3.0 (not
  the noctalia-qs `fb0cc155` fingerprint), and `coredumpctl list | grep -E 'quickshell|qs'`
  stays clean after a BT-disconnect repro.

## rpm-ostree kargs — persistence & stability caveats

General knowledge for anyone touching kernel arguments in this repo (`kargs.yml`) or
machine-locally via `rpm-ostree kargs`, not specific to the PSR issue above.

- **Persistence across image rebase:** kargs added machine-locally via
  `rpm-ostree kargs --append=...` (as opposed to this repo's `kargs.yml`, which is baked at
  build time) are stored in the deployment's origin file and are carried forward across both
  `rpm-ostree upgrade` and `rpm-ostree rebase` — the same mechanism that carries forward
  locally layered packages. Known footgun: chaining multiple rpm-ostree operations without
  letting one finish can silently drop kargs
  ([coreos/rpm-ostree#1392](https://github.com/coreos/rpm-ostree/issues/1392)). After any
  rebase, sanity-check with `rpm-ostree kargs` (no arguments) that expected overrides are
  still listed, rather than assuming.
- **`DC_DEBUG_MASK` / `DC_FEATURE_MASK` bitmasks are not ABI-stable.** Unlike named kernel
  boot parameters, these are raw bit positions into an internal, unversioned enum
  (`amd_shared.h`) intended for AMD's own driver bisection — there is no compatibility
  guarantee across kernel versions. A kernel bump can silently renumber or repurpose a bit
  with no boot-time error; the flag would then either do nothing or disable the wrong thing.
  Any karg that sets one of these masks should be re-verified against the matching kernel
  tag's `amd_shared.h` after a kernel version bump, not assumed stable indefinitely.
