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
