# Add Proton Pass Desktop and CLI from the official Proton channel

Status: Implemented · Proposed 2026-10-21 · Accepted 2026-10-21 · Committed 2026-10-21 (image build and runtime acceptance pending — task 10)

**Entry reconciliation (2026-10-21).** This repository has no `.doc-contract.toml`, no `docs/roadmap.md`, and no `docs/spec/`, so the `doc-contract` CLI refuses with `repo-root-mismatch` and the accept → begin → land sequence is carried in this file instead: acceptance is the status line above, entry reconciliation is this note, landing is the commit that adds the implementation. Manifest facts were re-verified at entry against the live vendor channels. One vendor move was found and is repaired here rather than papered over: `pass-cli` is now **2.5.1** (56,367,544 B, sha256 `40e27645e0485f5f0db928b81469d1c5a7c8968a162956e940069476244c02b1`, `pass-cli --version` → `Proton Pass CLI 2.5.1 (84186e7)`), not the 2.5.0 / 54,895,384 B recorded at proposal time; the desktop GUI is unchanged at 1.42.0-1 (rollout 1, sha512 `8b5523a6da4d29eb75c8d271911fac37e0b9e4acc1b8eacbd5c2a2797b99f5c2927bd0444f55f45359fe9feee2778639201dd2bd548876b7383775ac1f1a7582`, installed 390,913,189 B). Also re-confirmed unchanged: `rpm -Kv` reports header/payload digests only and no `SIGPGP`, `rpm -qp --scripts` is empty, `chrome-sandbox` is mode 0755 and not setuid, `/usr/bin/proton-pass` is a symlink to `../lib/proton-pass/Proton Pass`, both manifests are HTTP 200 and every `ReleaseDate` matches one ISO-8601 UTC shape, and the desktop file's `MimeType` is `x-scheme-handler/protonpass;` (slash) where this ticket's prose wrote a colon. No ADR or importer in this repository contradicts the intended work. The companion `add-1password` change was **dropped on 2026-10-21** before landing, so this change stands alone: the suite is 8 files, and there is no rebase ordering to track.

**Upstream dependencies:** Available: Proton's own Linux channel manifests — the desktop channel at `https://proton.me/download/PassDesktop/linux/x64/version.json` (fetched 2026-10-21, HTTP 200, 56,205 B, 67 releases; a `Releases[]` array of `{CategoryName, Version, ReleaseDate, RolloutPercentage, File[{Url, Sha512CheckSum, Args, Identifier}]}`) and the CLI channel at `https://proton.me/download/pass-cli/versions.json` (fetched 2026-10-21, HTTP 200, 1,183 B; `{formatVersion: 1, passCliVersions: {version, urls.linux.x86_64.{url, hash}}}`). Both manifests and every artifact URL they name were reachable, and both artifacts were downloaded and hash-verified on 2026-10-21 (GUI: newest Stable 1.42.0, release date 2026-10-07T10:26:40Z, rollout 1, RPM 120,309,189 B downloading to 390,913,189 B installed, package `proton-pass` 1.42.0-1; CLI: 2.5.1 at implementation time, single 56,367,544 B ELF binary, `pass-cli --version` → `Proton Pass CLI 2.5.1 (84186e7)`). The BlueBuild `script` module with `dnf5`, `rpm`, `curl`, `coreutils` (`sha512sum`/`sha256sum`/`od`/`install`), `stat`/`readlink`, and `findutils` (`find`) is available in the Fedora build container.
**Gated:** `jq` is required to parse both manifests and is **not** assumed present in the build container; the block installs it explicitly with `dnf5` (the vendor's own `install.sh` lists `curl` + `jq` as its Linux dependencies). The desktop RPM carries **no GPG signature** — `rpm -Kv` reports only `Header SHA256 digest: OK` and `Payload SHA256 digest: OK`, `SIGPGP=(none)` — and Proton publishes no signed RPM repository, so the manifest checksum plus TLS is the only integrity anchor; there is no `rpmkeys --checksig` step to perform. The RPM has **no scriptlets at all** (`rpm -qp --scripts` prints nothing), so no vendor repo file, polkit policy, or key import is created and cleaned up. Finally, the packaged `/usr/lib/proton-pass/chrome-sandbox` is mode `0755`, not setuid, and Electron therefore depends on unprivileged user namespaces for its Chromium sandbox; whether the app launches under niri and whether DMS surfaces its tray icon are **unverified today** and are acceptance observations, not build assertions.
**Dependents:** None in this repository. The browser extension and its native-messaging manifests, logging into Proton, `pass-cli ssh-agent` as a user service, and any niri/DMS dotfile change are operator actions after this image change lands and are not dependents of this ticket.
**Files owned:** `docs/changes/add-proton-pass/change.md`, `recipes/module-recipes/scripts.yml`, `tests/check-proton-pass-install.sh` (new), `AGENTS.md`, and `docs/layer-optimization.md`. The install goes inside the existing `scripts.yml` snippet (one snippet, one `dnf5 clean all`), so `recipes/recipe.yml` is **not** modified — module order is unchanged. No `files/system` content is added: there is no repo file, no polkit policy, and no service or desktop override to bake. User-owned state (`~/.config/proton-pass`, `~/.local/share/proton-pass`, keyrings, browser-extension state, niri config) is explicitly not owned.

## Why

Proton publishes no Fedora, RPM Fusion, or COPR package for Proton Pass. Its Linux channel is a pair of JSON manifests under `proton.me/download/` that name per-version files, plus a vendor shell install script for the CLI. `dnf.yml` is the canonical place for repo-available packages, so there is nothing for it to install here, and the documented `scripts.yml` escape hatch is the only layer that fits. A new module recipe would add a `recipe.yml` ordering dependency for one install block and buy nothing.

Proton Pass has two official Linux artifacts and this change installs both. The **GUI** is a real official Electron desktop application for Linux: the manifest's newest Stable entry today is 1.42.0, whose `.rpm (Fedora/RHEL)` file is a 120 MB RPM producing `/usr/bin/proton-pass` → `/usr/lib/proton-pass/Proton Pass`, a `/usr/share/applications/proton-pass.desktop` with `Exec=proton-pass %U` and `MimeType=x-scheme-handler/protonpass;`, and no autostart or `TryExec` key. The **CLI** is a separate single Rust binary, `pass-cli`, for which Proton publishes **no** RPM and no deb — only a binary per version, plus an `install.sh` that resolves the manifest, checks `formatVersion == 1`, downloads, compares sha256, and drops the file in `$PROTON_PASS_CLI_INSTALL_DIR`, `~/.local/bin`, or `/usr/local/bin`. Both are official Proton channels; the Flatpak and Snap are not (see **Rejected alternatives**).

The verification mechanism is weaker than a signed package channel, and saying so is the point rather than an oversight. Proton publishes neither a repository nor a signed RPM, only per-version files plus a checksum manifest, so the strongest thing available is: fetch the manifest, select the artifact entry, download, and verify the hash **listed in that same manifest**. A manifest-sourced checksum shares an origin with the artifact it describes, so it reliably catches corruption, a truncated download, and a retargeted or redirected URL — it becomes a build failure instead of an install — but it does **not** defend against compromise of `proton.me` or of the release process. No signature means no independent origin check. The ticket states this so a future maintainer does not read the hash check as equivalent to a package signature, and so nobody "improves" it by inventing a pin that merely freezes the same unverified bytes.

Updates are image-only. The installed GUI and CLI are the vendor artifacts, unmodified, under immutable `/usr`, and this change deliberately ships **no** update shim: no wrapper binary, no `pass-cli update` interception, no Electron `autoUpdater` patch. `pass-cli update` cannot persist on `/usr` and the GUI's updater cannot write its own installation, so both are expected to fail or refuse; what they actually print is recorded at acceptance rather than asserted at build time. Leaving the binary byte-identical is what keeps the manifest-hash and version assertions meaningful.

## Dropped sibling change

A companion `add-1password` change was drafted immediately before this ticket and touched the same three files, but it was **dropped on 2026-10-21** before landing: Proton Pass alone covers the password-manager role for this image. There is therefore no second vendor channel to coordinate with, no rebase ordering to track, and no shared "8 vs 9" test-file count; the suite is 8 files, and `docs/layer-optimization.md` records the accepted vendor-latest channels as Bitwarden, then Proton Pass. The decision is recorded here because this repository has no `docs/roadmap.md` to carry it.

## What changes

### Δ ADDED

- Add a Proton Pass block to the existing script snippet in `recipes/module-recipes/scripts.yml`, immediately before the single final `dnf5 clean all`. The block:
  - installs `jq` (build-time manifest parser) with `dnf5` if it is absent, because neither the recipe nor `AGENTS.md` may assume the build container already has it;
  - resolves the **GUI** from `https://proton.me/download/PassDesktop/linux/x64/version.json`: selects the newest entry whose `CategoryName` is exactly `"Stable"` by `ReleaseDate`, then within its `File[]` selects the single entry whose `Identifier` is `.rpm (Fedora/RHEL)`; logs the resolved `Version` and `RolloutPercentage`; fails closed if there is no Stable entry, no RPM file, or more than one RPM file;
  - downloads that RPM to `/tmp`, asserts it is non-empty, verifies the manifest `Sha512CheckSum` with `sha512sum -c`, asserts the downloaded RPM's `%{NAME}` is `proton-pass` and its `%{VERSION}` is the manifest `Version` (with `%{VERSION}-%{RELEASE}` asserted as `<version>-1`, the vendor's current release-suffix convention), installs it with `dnf5 install -y`, and deletes the temporary file;
  - resolves the **CLI** from `https://proton.me/download/pass-cli/versions.json`: asserts `formatVersion == 1` (mirroring the vendor script's own guard), reads `.passCliVersions.version` and `.passCliVersions.urls.linux.x86_64.{url,hash}`;
  - downloads the CLI binary to `/tmp`, verifies the manifest sha256 with `sha256sum -c`, asserts the file is a non-empty ELF (`7f454c46` magic), installs it with `install -Dm0755` to `/usr/bin/pass-cli`, and deletes the temporary file;
  - asserts the result against the **manifest-derived shell variables**, never a second hardcoded literal: `rpm -q proton-pass` reports the resolved GUI version, `/usr/bin/proton-pass` resolves to `/usr/lib/proton-pass/Proton Pass`, `/usr/share/applications/proton-pass.desktop` exists, `/usr/bin/pass-cli --version` contains the resolved CLI version, `/usr/local/bin/pass-cli` does not exist, `chrome-sandbox` is still `0755` and not setuid, no vendor repo file appeared, and no Proton account/session state was created under the build's `HOME`.
  - records four explicit **non-actions** with reasons: do not set the setuid bit on `chrome-sandbox`, do not pass `--no-sandbox`, do not run the vendor `install.sh` (and never pipe it into `bash`), and do not touch `/usr/local`.

  Landed block — inserted verbatim inside the existing snippet, immediately before the single final
`dnf5 clean all`, on 2026-10-21. The only deltas from the proposal draft are the `Last validated`
annotation moving to CLI 2.5.1, the 1Password cross-reference sentence removed when that ticket was
dropped, and the `HOME` state scan capturing its output so a failing `find` cannot read as "no state found":

  ```bash
  # Install Proton Pass Desktop + CLI from Proton's official channel.
  # Proton publishes no Fedora/RPM Fusion/COPR package, no GPG-signed RPM, and
  # no signed repository, so scripts.yml is the documented escape hatch. The
  # integrity anchor is the checksum listed in the same vendor manifest that
  # names the URL: that catches corruption, truncation, and a retargeted
  # download, but it shares an origin with the artifact and is NOT a signature
  # check. Do not replace this with a Flatpak/Snap community wrapper or a
  # third-party repack.
  # Resolved-latest policy: both manifests are re-read whenever this layer
  # re-executes, so a rebuild picks up Proton's current Stable desktop build
  # and current pass-cli. The layer still caches, so resolution happens on a
  # cache-invalidating change, not on every trivial rebuild.
  # Last validated 2026-10-21: desktop 1.42.0 (rollout 1), CLI 2.5.1.
  PASS_GUI_MANIFEST_URL="https://proton.me/download/PassDesktop/linux/x64/version.json"
  PASS_CLI_MANIFEST_URL="https://proton.me/download/pass-cli/versions.json"

  # jq parses both manifests. The vendor's own install.sh lists curl + jq as
  # its Linux dependencies; do not assume the build container ships jq.
  command -v jq >/dev/null || dnf5 install -y jq

  # Newest entry whose CategoryName is exactly "Stable". RolloutPercentage
  # governs gradual delivery of a build to existing clients, not artifact
  # validity, so it is logged and never used as a filter. No Stable entry, no
  # RPM file, or more than one RPM file all fail the build: never fall back to
  # the Beta channel. sort_by(.ReleaseDate) relies on every entry carrying the
  # same ISO-8601 UTC shape, which all 67 do today; the NVR assertions below
  # still compare against whatever the selection produced.
  PASS_GUI_MANIFEST="/tmp/proton-pass-version.json"
  curl -fL "${PASS_GUI_MANIFEST_URL}" -o "${PASS_GUI_MANIFEST}"
  test -s "${PASS_GUI_MANIFEST}"
  test "$(jq '[.Releases[] | select(.CategoryName == "Stable")] | length' "${PASS_GUI_MANIFEST}")" -gt 0
  PASS_STABLE='[.Releases[] | select(.CategoryName == "Stable")] | sort_by(.ReleaseDate) | last'
  PASS_VERSION="$(jq -er "${PASS_STABLE} | .Version" "${PASS_GUI_MANIFEST}")"
  PASS_ROLLOUT="$(jq -er "${PASS_STABLE} | .RolloutPercentage" "${PASS_GUI_MANIFEST}")"
  PASS_RPM_FILE="${PASS_STABLE} | .File[] | select(.Identifier == \".rpm (Fedora/RHEL)\")"
  test "$(jq "[${PASS_RPM_FILE}] | length" "${PASS_GUI_MANIFEST}")" -eq 1
  PASS_RPM_URL="$(jq -er "${PASS_RPM_FILE} | .Url" "${PASS_GUI_MANIFEST}")"
  PASS_RPM_SHA512="$(jq -er "${PASS_RPM_FILE} | .Sha512CheckSum" "${PASS_GUI_MANIFEST}")"

  # Constraint 1 enforced mechanically: a manifest that points somewhere other
  # than proton.me stops the build instead of fetching whatever it names.
  case "${PASS_RPM_URL}" in
    https://proton.me/*) ;;
    *) echo "unexpected Proton Pass RPM host: ${PASS_RPM_URL}" >&2; exit 1 ;;
  esac

  PASS_RPM="/tmp/proton-pass.rpm"
  echo "Installing Proton Pass ${PASS_VERSION} (rollout ${PASS_ROLLOUT}%): ${PASS_RPM_URL}"
  curl -fL "${PASS_RPM_URL}" -o "${PASS_RPM}"
  test -s "${PASS_RPM}"
  # No SIGPGP on this RPM (rpm -Kv: header/payload digests only), so the manifest
  # Sha512CheckSum is the anchor. errexit is on in this snippet (`set -oue
  # pipefail` at the top of scripts.yml), but this is the trust boundary, so it
  # fails explicitly rather than merely relying on errexit.
  printf '%s  %s\n' "${PASS_RPM_SHA512}" "${PASS_RPM}" | sha512sum -c - \
    || { echo "Proton Pass RPM sha512 mismatch" >&2; exit 1; }
  # A retargeted or renamed file must fail here, not silently install something
  # else. Proton currently publishes <version>-1; a different release suffix
  # stops the build for deliberate review.
  test "$(rpm -qp --qf '%{NAME}' "${PASS_RPM}")" = "proton-pass"
  test "$(rpm -qp --qf '%{ARCH}' "${PASS_RPM}")" = "x86_64"
  test "$(rpm -qp --qf '%{VERSION}' "${PASS_RPM}")" = "${PASS_VERSION}"
  test "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "${PASS_RPM}")" = "${PASS_VERSION}-1"
  dnf5 install -y "${PASS_RPM}"
  rm -f "${PASS_RPM}"

  # pass-cli is a single Rust binary and Proton publishes no RPM/deb for it.
  # Replicate the deterministic steps of the vendor install.sh (fetch manifest,
  # check formatVersion, download, verify sha256, install) instead of piping
  # that script into a root shell inside the image build.
  PASS_CLI_MANIFEST="/tmp/pass-cli-versions.json"
  PASS_CLI_BIN="/tmp/pass-cli"
  curl -fL "${PASS_CLI_MANIFEST_URL}" -o "${PASS_CLI_MANIFEST}"
  test -s "${PASS_CLI_MANIFEST}"
  # The vendor install.sh refuses any formatVersion other than 1; mirror that so
  # a schema change stops the build instead of reading the wrong fields.
  test "$(jq -er '.formatVersion' "${PASS_CLI_MANIFEST}")" = "1"
  PASS_CLI_VERSION="$(jq -er '.passCliVersions.version' "${PASS_CLI_MANIFEST}")"
  PASS_CLI_URL="$(jq -er '.passCliVersions.urls.linux.x86_64.url' "${PASS_CLI_MANIFEST}")"
  PASS_CLI_SHA256="$(jq -er '.passCliVersions.urls.linux.x86_64.hash' "${PASS_CLI_MANIFEST}")"
  # The manifest key really is `.hash` (verified 2026-10-21: keys are ["hash","url"]),
  # not `.sha256`; jq -er fails closed if that ever changes shape.
  case "${PASS_CLI_URL}" in
    https://proton.me/*) ;;
    *) echo "unexpected pass-cli host: ${PASS_CLI_URL}" >&2; exit 1 ;;
  esac
  echo "Installing Proton Pass CLI ${PASS_CLI_VERSION}: ${PASS_CLI_URL}"
  curl -fL "${PASS_CLI_URL}" -o "${PASS_CLI_BIN}"
  test -s "${PASS_CLI_BIN}"
  printf '%s  %s\n' "${PASS_CLI_SHA256}" "${PASS_CLI_BIN}" | sha256sum -c - \
    || { echo "pass-cli sha256 mismatch" >&2; exit 1; }
  test "$(od -An -tx1 -N4 "${PASS_CLI_BIN}" | tr -d ' \n')" = "7f454c46"
  # /usr/bin, not /usr/local/bin: on this atomic image /usr/local is a symlink
  # to /var/usrlocal, which is not the image-owned tree. /usr is.
  install -Dm0755 "${PASS_CLI_BIN}" /usr/bin/pass-cli
  rm -f "${PASS_CLI_BIN}" "${PASS_GUI_MANIFEST}" "${PASS_CLI_MANIFEST}"

  # Assert against the versions the manifests just supplied, not a second
  # hardcoded literal. --version is safe: the CLI fails closed without a
  # session ("This operation requires an authenticated client") and writes no
  # state.
  rpm -q proton-pass
  test "$(rpm -q --qf '%{VERSION}-%{RELEASE}' proton-pass)" = "${PASS_VERSION}-1"
  test -x /usr/bin/proton-pass
  test "$(readlink -f /usr/bin/proton-pass)" = "/usr/lib/proton-pass/Proton Pass"
  test -f /usr/share/applications/proton-pass.desktop
  /usr/bin/pass-cli --version | grep -F "Proton Pass CLI ${PASS_CLI_VERSION}"
  test ! -e /usr/local/bin/pass-cli

  # Leave the vendor artifact's security posture alone. The package ships
  # chrome-sandbox mode 0755 with no setuid bit, so Chromium relies on
  # unprivileged user namespaces. Do NOT "fix" this here (no chmod u+s, no
  # --no-sandbox); a launch failure is a separate follow-up decision.
  test "$(stat -c '%a' /usr/lib/proton-pass/chrome-sandbox)" = "755"
  test ! -u /usr/lib/proton-pass/chrome-sandbox

  # The RPM has no scriptlets, so nothing wrote a vendor repo file or imported a
  # key; --version must not have created account/session state either.
  test ! -e /etc/yum.repos.d/proton.repo
  # Capture the scan before testing it: if find itself fails (unset or
  # unreadable HOME), an inline `test -z "$(find ...)"` would read the empty
  # result as "no state found" and pass vacuously.
  PASS_HOME_STATE="$(find "${HOME}" -maxdepth 4 \
    \( -iname '*proton*' -o -iname 'pass-cli*' \) -print -quit)" \
    || { echo "Proton Pass state scan failed under ${HOME}" >&2; exit 1; }
  test -z "${PASS_HOME_STATE}"
```

- Add `tests/check-proton-pass-install.sh`, a bash intent test in the shape of `tests/check-bettbox-install.sh` and `tests/check-bitwarden-install.sh`, asserting the literals the recipe actually contains: both manifest URLs, the `"Stable"` selection, the `.rpm (Fedora/RHEL)` identifier, `sha512sum -c -`, `sha256sum -c -`, the `formatVersion` guard, `install -Dm0755 "${PASS_CLI_BIN}" /usr/bin/pass-cli`, `dnf5 install -y "${PASS_RPM}"`, `rpm -q proton-pass`, `pass-cli --version`, that `dnf5 clean all` occurs exactly once and is the last non-blank line of the snippet, that `scripts.yml` precedes `systemd.yml`, and that the Bettbox, CC Switch, Chipmunk, Bitwarden, and terra blocks are still present. It negatively asserts: no `flatpak`/`snap` installation of Proton Pass, no `curl`-into-`bash` of the vendor `install.sh`, no `/usr/local/bin/pass-cli`, no `chmod`/`u+s` **targeting `/usr/lib/proton-pass/chrome-sandbox`** (the negative is path-scoped: the pre-existing `chmod u+s /usr/share/Bettbox/BettboxCore` line in `scripts.yml` must stay untouched, so a bare `u+s` grep would fail today), no `--no-sandbox`, an off-host manifest URL, and no baked Proton account/session/token state. It deliberately does **not** assert the absence of other vendors' literals anywhere in `scripts.yml`: that file is shared, so a whole-file negative would break the moment any sibling install block lands.
- Record the runtime requirements and observations (sandbox launch under niri, tray/StatusNotifierItem visibility, self-update behaviour) in this change item. No separate `docs/proton-pass.md` is added.

### Δ MODIFIED

- Extend the `scripts.yml` bullet in `AGENTS.md` with the additional install pattern this block introduces: **vendor manifest + checksum-verified download** (resolve latest from the vendor JSON manifest, select the platform artifact, verify the manifest checksum, install, assert against the resolved version). Name `tests/check-proton-pass-install.sh` as the coupled test, and qualify the same bullet's statement that "The RPM URLs are pinned constants (nothing is resolved at build time)" — that holds for the GitHub release pins only; the vendor-manifest and vendor-latest blocks resolve at build time.
- Update the "Run the whole suite (7 files)" count in `AGENTS.md` to **8**. Adjust the parenthetical example list only if needed; it is illustrative, not exhaustive.
- Update `docs/layer-optimization.md` section B to record Proton Pass as the accepted vendor-latest channel alongside Bitwarden (the layer caches and only changes when the vendor ships a release), with the size delta: GUI 120,309,189 B downloaded / 390,913,189 B installed, plus 56,367,544 B for the `pass-cli` binary — roughly 447 MB installed and 177 MB downloaded per cache-invalidating rebuild. Note it is a size consideration, not a reason to block the change.
- Leave the recipe module order unchanged: `files.yml` first, `scripts.yml` before `systemd.yml`, `signing` last. `recipes/recipe.yml` is not edited.

### Δ REMOVED

- None.
- In particular, do not remove or modify the Bettbox, CC Switch, Chipmunk, Bitwarden, or terra blocks, and do not collapse them into the new block. Do not add a second `dnf5 clean all`.

## Design constraints

1. **Official Proton channel only.** Everything comes from `proton.me/download/`. The Flatpak (`me.proton.Pass`) and Snap (`proton-pass`) are community wrappers whose own metadata says the build is "not verified, affiliated with, or supported by Proton AG" — rejected. nixpkgs, COPR, and any repack are rejected. The block enforces this mechanically with a `case` guard on each resolved URL: anything outside `https://proton.me/` stops the build.
2. **Resolve latest from the vendor manifest, verify against that manifest.** No literal version pin. The GUI version, URL, and SHA-512 all come from `PassDesktop/linux/x64/version.json`; the CLI version, URL, and SHA-256 all come from `pass-cli/versions.json`. A pin would freeze an unverified artifact and stop security updates, without adding any trust the manifest does not already carry.
3. **The manifest checksum is the integrity anchor, and its limits are stated.** The GUI RPM is not GPG-signed (`SIGPGP=(none)`); Proton has no signed repo, so no key import and no `rpmkeys --checksig` exists to perform. The manifest and the artifact share an origin: the hash catches corruption, truncation, and a retargeted or renamed download — it does not detect origin compromise. This change is not a signature check and does not claim to be.
4. **Both artifacts, one block, one cleanup.** The GUI RPM and the CLI binary are installed by the same snippet, before the single existing `dnf5 clean all`. Temp files are removed individually and the CLI manifest/temp paths are removed at the end.
5. **Fail closed on manifest drift.** No Stable entry, no `.rpm (Fedora/RHEL)` file, more than one such file, `formatVersion != 1`, a missing URL/hash field, a name mismatch, a version mismatch, or a hash mismatch stops the build. Nothing falls back to Beta, to a different architecture, or to a different artifact type.
6. **Never execute the vendor install script.** `install.sh` is read as documentation and its deterministic steps are replicated (fetch manifest, check `formatVersion`, download, verify sha256, install mode 0755 with `install`, assert). Piping unpinned remote shell into a root shell inside the image build is not acceptable; `curl … | bash` must appear nowhere in the recipe.
7. **`/usr/bin/pass-cli`, not `/usr/local/bin/pass-cli`.** On this atomic image `/usr/local` is a symlink to `/var/usrlocal`, so the vendor default target is the wrong tree. `/usr` is image-owned and immutable, which is also why updates are image-only.
8. **Do not change the vendor artifact's security posture.** `chrome-sandbox` stays mode `0755` with no setuid bit, exactly as shipped, and no `--no-sandbox` flag is added anywhere. Whether Electron's sandbox works under niri through unprivileged user namespaces is observed at acceptance; if it fails, the choice between setuid and `--no-sandbox` is a separate follow-up decision, not something this ticket does silently.
9. **Image-only upgrades, documented not implemented.** No wrapper binary, no shim in front of `pass-cli`, no Electron `autoUpdater` patch. `pass-cli update` and the GUI's updater cannot persist under immutable `/usr`; the installed binary stays byte-identical to the vendor artifact so the manifest-hash and `--version` assertions stay honest. The observed behaviour of both updaters is an acceptance record.
10. **No secrets or user state in the image.** No login, no session, no personal access token, no keyring, no `~/.config/proton-pass`, no `~/.local/share/proton-pass`, no browser-extension host manifest. The build only runs `pass-cli --version`, which fails closed without a session and creates nothing; the GUI binary is never launched during the build.
11. **Assertions compare against the manifest, not a second literal.** Versions live in shell variables derived from the manifests and are reused in every assertion, so a vendor version move is a build-time fact rather than an edit someone must remember.
12. **No repository is enabled, persisted, or removed.** The RPM has no scriptlets, so no vendor repo file is written, no polkit policy is rendered, and no key is imported — there is nothing to clean up and nothing left behind in `/etc`.
13. **Runtime dependencies come from the enabled Fedora repos.** `dnf5` resolves the RPM's `gtk3`, `nss`, `libnotify`, `libXtst`, `libxcb`, `mesa-libgbm`, `at-spi2-core`, `libdrm`, `xdg-utils`, and trash backend (`kde-cli-tools`, which Kinoite provides) from the repositories the recipe already configures. `dnf.yml` is not modified; if a dependency were genuinely missing the build fails loudly rather than being patched around here.

## Rejected alternatives

- **Flatpak (`me.proton.Pass`).** A community wrapper, not a Proton build; its metadata disclaims verification, affiliation, and support by Proton AG. Wrong channel under constraint 1.
- **Snap (`proton-pass`).** Same problem, same disclaimer. Also pulls snapd lifecycle into an atomic image that does not want it.
- **nixpkgs / COPR / Terra repack.** Third-party redistribution of a password manager; an unverified rebuild of the vendor binary, excluded outright.
- **Literal pinned version URL and hash committed to the recipe.** Mechanically possible — the manifest exposes per-version URLs — but it freezes security updates and adds no trust: the committed hash would be transcribed from the same manifest, so it protects nothing the manifest lookup does not. Chosen instead: resolve latest per build, verify the manifest hash.
- **Running `install.sh` (or `curl … | install.sh | bash`).** Executes unpinned remote shell as root inside the image build, and its default targets (`/usr/local/bin`, `~/.local/bin`) are wrong for this layout. Its deterministic steps are replicated instead.
- **Installing the CLI to `/usr/local/bin`.** On this image `/usr/local` → `/var/usrlocal`; the binary would land outside the image-owned tree and would not be part of the signed, immutable content.
- **Setting the setuid bit on `chrome-sandbox`, or launching with `--no-sandbox`.** Both change the vendor's security posture. Documented and observed instead.
- **A wrapper binary or shim implementing self-update.** It would break the "installed bytes equal the vendor artifact" property that makes hash and version assertions meaningful, and it cannot write `/usr` anyway.
- **The Beta channel.** Not this image's policy; Beta is not selected even if a Beta entry is newer.
- **Silently falling back to Beta (or to any other file) when no Stable RPM exists.** The build fails closed instead.
- **rpm-ostree layering.** Not this image's model; all software is baked at build time and the image is rebuilt to update.

## Tasks

1. **[done — re-verified 2026-10-21 from this host. Result: no Fedora/RPM Fusion/COPR package for either artifact; desktop Stable 1.42.0 (rollout 1), RPM `proton-pass-1.42.0-1.x86_64`, sha512 `8b5523a6…7582`, 120,309,189 B; CLI **2.5.1** (moved from the 2.5.0 recorded at proposal time), sha256 `40e27645…02b1`, 56,367,544 B. Both artifacts were downloaded and hash-verified. See the entry note at the top.]** Re-confirm availability before implementing (per `AGENTS.md`, run this check from a Fedora host first): `dnf5 search proton-pass`, `dnf5 repoquery --info proton-pass`, and a look at RPM Fusion `nonfree` plus the `scottames/ghostty` and `avengemedia/dms` COPRs. Fetch both manifests and record the current Stable desktop version, rollout percentage, RPM URL and SHA-512, plus the CLI version, URL, and SHA-256. Record the results in this ticket; re-run the check if implementation is delayed past 2026-10-21.
2. **[done]** Append the GUI half of the block to the existing snippet in `recipes/module-recipes/scripts.yml`, immediately before the single final `dnf5 clean all`: install `jq` if absent, fetch the PassDesktop manifest, select the newest `"Stable"` entry, select the single `.rpm (Fedora/RHEL)` file, log version and rollout, and fail closed on missing/ambiguous entries.
3. **[done]** Add the GUI download/verify/install steps: `curl -fL` to `/tmp/proton-pass.rpm`, non-empty check, `sha512sum -c -` against the manifest `Sha512CheckSum` with an explicit failure branch (do not lean on errexit alone for the trust boundary), `%{NAME}`/`%{ARCH}`/`%{VERSION}`/`%{VERSION}-%{RELEASE}` assertions, the `https://proton.me/` host guard on the resolved URL, `dnf5 install -y`, then `rm -f` the temp RPM.
4. **[done]** Add the CLI half: fetch `pass-cli/versions.json`, assert `formatVersion == 1`, read version/url/hash (the key is literally `.hash`), apply the host guard, download, `sha256sum -c -` with an explicit failure branch, ELF magic check, `install -Dm0755 … /usr/bin/pass-cli`, then remove the temp binary and both manifests.
5. **[done]** Add the assertion block described in **What changes**, keeping every expected version in a manifest-derived shell variable. Do not add a second `dnf5 clean all`, and do not re-enable or leave any repository behind (nothing is enabled by this block). Keep the block's `Last validated <date>` annotation current whenever the resolution is re-checked: it records when the resolved versions were last confirmed, not a pin to bump.
6. **[done]** Keep the four non-actions explicit and commented where a maintainer will read them: no setuid on `chrome-sandbox`, no `--no-sandbox`, no vendor `install.sh`, no `/usr/local` write. The comment must say *why* the sandbox bit is deliberately absent.
7. **[done — and hardened by an orchestrator audit after the first implementation. That audit found the test could be made vacuous: commenting out the `readlink` assertion, the vendor-repo assertion, or a hash failure branch left the suite green, because only the literals enumerated here were covered. Every assertion the ticket requires is now grepped as an executable (comment-stripped) line, so disabling one fails the test. Verified by mutation, not by inspection.]** Add `tests/check-proton-pass-install.sh` covering the positive literals (including the `command -v jq` install line and the `https://proton.me/` host guard), the negative assertions with the `chrome-sandbox` negative scoped to its own path (and no whole-file negative on other vendors' literals), the `dnf5 clean all` once-and-last check, `scripts.yml` before `systemd.yml`, and the untouched Bettbox / CC Switch / Chipmunk / Bitwarden / terra blocks. Run it, then run the whole suite.
8. **[done]** Update `AGENTS.md`: extend the `scripts.yml` bullet with the manifest-verified vendor pattern and the new test, qualify the "pinned constants" sentence, and bump the suite file count to 8.
9. **[done]** Update `docs/layer-optimization.md` section B with the new accepted vendor-latest channel and the size delta (roughly 447 MB installed / 177 MB downloaded) as a stated consideration rather than a blocker.
10. **[open — needs a push, a CI build, a booted image, and a real Proton account. Nothing in the repository blocks it; this is the only unfinished task. Note when taking it: `chrome-sandbox` ships 0755 and non-setuid (verified on the artifact), so an Electron launch failure under niri would be the setuid-vs-`--no-sandbox` follow-up decision named in constraint 8, not a defect in this change.]** Push and let CI build and sign the image; record the resolved desktop and CLI versions and the built-image evidence in this change item. Then perform runtime acceptance under niri and record the observations (launch under Wayland, tray/StatusNotifierItem visibility, `pass-cli` commands against a real account, what `pass-cli update` and the GUI update check actually report). Keep this change item as repository history: this repository has **no `docs/roadmap.md`** and **no `.doc-contract.toml` / installed doc-contract archive workflow**, so there is no roadmap line to add and no archive step to run — the ticket stays in `docs/changes/add-proton-pass/` as the record.

## Verify

- `bash tests/check-proton-pass-install.sh` passes.
- All existing `tests/check-*.sh` scripts still pass: `for t in tests/check-*.sh; do bash "$t"; done`.
- The recipe schema remains valid: CI's build is the gate; locally, `bluebuild build ./recipes/recipe.yml` (`AGENTS.md`'s documented command) if the CLI is installed. CI builds and signs the image.
- Built image, GUI:
  - `rpm -q proton-pass` reports the version that the manifest carried at build time (1.42.0 as of 2026-10-21).
  - `/usr/bin/proton-pass` resolves to `/usr/lib/proton-pass/Proton Pass`.
  - `/usr/share/applications/proton-pass.desktop` exists and parses (`desktop-file-validate` if available; at minimum it contains `Exec=proton-pass %U` and `MimeType=x-scheme-handler/protonpass;`).
  - `/usr/lib/proton-pass/chrome-sandbox` is mode `0755` and **not** setuid — i.e. no bit was added by this change — and no `--no-sandbox` flag exists in the recipe.
- Built image, CLI:
  - `/usr/bin/pass-cli --version` contains the manifest CLI version (2.5.1 as of 2026-10-21).
  - `/usr/bin/pass-cli` is on the image-owned tree; `/usr/local/bin/pass-cli` does not exist.
- No baked state: no Proton Pass config, session, personal access token, keyring, or browser native-messaging host under `/root`, `/home/*`, or `files/system`; `scripts.yml` contains no login/token handling. No `/etc/yum.repos.d/proton.repo` appeared.
- Runtime acceptance under niri (DMS launcher):
  - Launch Proton Pass. Record whether the Electron window comes up under Wayland, and whether a tray/StatusNotifierItem icon appears in DMS. If it does not launch, record the failure verbatim and note that the sandbox decision (setuid vs `--no-sandbox`) is an out-of-scope follow-up, not a fix to smuggle into this change.
  - Log in, then run `pass-cli login`, `pass-cli info`, and `pass-cli ssh-agent start|load` against a real account and record the results.
  - Record what `pass-cli update` reports (expected to fail or refuse because `/usr` is immutable) and what the GUI's own update check reports. Do not implement any update path in response.
- Invariant spot-check: `scripts.yml` still precedes `systemd.yml` in `recipes/recipe.yml`; `files.yml` still runs first and `signing` last; the Bettbox, CC Switch, Chipmunk, Bitwarden, and terra blocks are untouched; the image remains CI-built, signed, documentation-change-skipping, and free of user secrets.

## Out of scope

- The Proton Pass browser extension and any native-messaging host manifest.
- Logging into Proton inside the image, or baking any account, session, personal access token, or keyring state.
- Niri config, DMS config, or any other user dotfile, including the tray host.
- A systemd user unit for `pass-cli ssh-agent` daemon mode.
- The Flatpak and Snap community wrappers.
- The Beta channel.
- Implementing self-update: no wrapper, no shim, no `autoUpdater` patch, no vendor `install.sh` execution. Documented and observed only.
- Setting the Chromium setuid sandbox bit or adding `--no-sandbox`.
- `pass-cli agent` (AI agent) wiring.
- `docs/proton-pass.md`.
- Any runtime `dnf` or other self-update path.
- Third-party repackaging (nixpkgs, COPR, Terra/Fyra Labs) of either artifact.
