---
id: grok-bot-signed-channel
status: landed
persistence: ephemeral
depends_on:
  - add-grok-bot
files_owned:
  - docs/changes/grok-bot-signed-channel/change.md
  - recipes/module-recipes/scripts.yml
  - tests/check-grok-bot-install.sh
  - AGENTS.md
  - docs/layer-optimization.md
accepted_at: 2026-11-01
started_at: 2026-11-01
landed_at: 2026-11-01
archive_path: docs/changes/archive/2026-11-01-grok-bot-signed-channel
---
# Install Grok Bot from the vendor's signed yum repo

Status: Landed · 2026-11-01

**Upstream dependencies:** The vendor's yum repo (`https://downloads.cursor.com/yumrepo/grok-bot`)
publishes signed `grok-bot` RPMs and a signed `repomd.xml`; its signing key is served at
`https://downloads.cursor.com/keys/anysphere.asc`. The block's shape reuses the terra-repo pattern
already in `scripts.yml` (enable a vendor repo for the install, disable it again so it does not
survive into the image). Container verification used `fedora:44` under rootless `podman`, whose
`dnf5` behaves as the BlueBuild build stage's does.
**Dependents:** None in this repository. Nothing else reads Grok Bot's pin.

## Why

The build is red, and it is red by design: `main` fails in the `script` module with

```
Grok Bot pin is stale: stable channel now serves …/grok-bot-0.78.1-1.x86_64.rpm
Re-pin grok-bot after review: URL, sha256, and the version/date annotation.
```

The `grok-bot-drift-tripwire` change installed that tripwire because the pinned artifact was the
only trustworthy channel: the download-page RPM carries no OpenPGP signature (`rpm -Kv` reports
header/payload digests only), so a committed sha256 was the strongest anchor available, and the
stable-channel endpoint was resolved only to notice when the pin had gone stale.

That premise has expired. As of 2026-10-31 the vendor's yum repo carries `grok-bot 0.78.1-1` for
x86_64 — the same version the download page serves — and the two RPMs have an identical payload
digest (`b8104a4c…`), differing only by the OpenPGP signature header the repo build carries. The
repo's `repomd.xml` is signed too, and the key is published. So the signed channel leads, and a
committed *artifact* hash is no longer the right anchor: a signature covers every future artifact,
where a hash covers exactly one.

This change therefore swaps the mechanism rather than bumping the pin: Grok Bot installs from the
signed repo, the committed anchor moves from the artifact to the vendor's signing key, and the
drift tripwire retires because there is no longer a pin to drift.

## Design constraints

1. **The trust root is committed, not "TLS today".** The key is fetched at build time but verified
   against a committed sha256 before dnf is allowed to use it, and `gpgkey=` points dnf at that
   verified file. Fetching the key straight from the URL and letting dnf import it (TOFU) would
   have made whatever the URL served that minute the root of trust.
2. **Signature verification is dnf's, and it is load-bearing.** `repo_gpgcheck=1` covers
   `repomd.xml`, `gpgcheck=1` covers the RPM. Verified in a throwaway container: pointing
   `gpgkey=` at a key that does not sign the repo fails the transaction with
   `Signature verification failed … wrong key?` and installs nothing. A build-time assertion that
   cannot fail is decoration, so this was proven by making it fail.
3. **Vendor-latest is a stated exception, not a default.** Resolution happens when the layer
   re-executes; the layer still caches, so churn equals "the vendor published". This joins the
   Bitwarden and Proton Pass channels recorded in `docs/layer-optimization.md` rather than
   contradicting that policy.
4. **No second version literal.** The installed NVR is asserted against the version this build's
   repo actually offered, held in a shell variable — the Proton Pass pattern. A hardcoded
   `0.78.1-1` would only be compared against itself next week.
5. **The vendor repo does not survive into the image.** `/usr` is immutable, so the repo the
   `%post` registers cannot serve an in-place update; it is disabled exactly as before.
6. **Nothing else about the block changes.** The Electron sandbox posture is still the vendor
   scriptlet's business, the install order between Chipmunk and Proton Pass is unchanged, and the
   shared `dnf5 clean all` stays the last executable line.

## What changes

### Δ ADDED

- The Grok Bot block fetches the vendor key, verifies it against a committed sha256, writes a
  build-time `/etc/yum.repos.d/grok-bot-vendor.repo` with `gpgcheck=1`, `repo_gpgcheck=1` and
  `gpgkey=file://<verified key>`, resolves the newest signed version with
  `dnf5 --assumeyes repoquery --latest-limit 1`, installs with `dnf5 install -y grok-bot`, then
  asserts the installed NVR equals the resolved one, the arch is `x86_64`, and the imported key's
  fingerprint is the reviewed one.
- A shape guard on the resolve: dnf prints its repository banner on stdout, and a repo whose
  `repomd.xml` cannot be verified resolves to nothing — so an empty or non-version result fails
  the build with the reason rather than installing from a repo that silently loaded nothing.

### Δ MODIFIED

- `recipes/module-recipes/scripts.yml`: the Grok Bot block is rewritten in place (same position).
- `tests/check-grok-bot-install.sh`: rewritten for the new mechanism — key-hash verification
  precedes repo creation, which precedes the install; `gpgcheck`/`repo_gpgcheck`/`gpgkey=file://`
  are asserted; the retired artifact pin, the retired channel tripwire and the retired
  `dnf5 install -y "${GROK_BOT_RPM}"` local-file install become negative assertions.
- `AGENTS.md`: the `scripts.yml` paragraph's Grok Bot clause describes the signed channel and the
  key-hash anchor instead of the unsigned pin plus tripwire.
- `docs/layer-optimization.md` (frozen): Grok Bot moves from the pinned-URL paragraph to the
  vendor-latest list, and the "candidate migration once it stops lagging" note is resolved.
  Re-stamped after the reviewed edit.

### Δ REMOVED

- The pinned artifact URL, its committed sha256, and the `rpm -qp` identity asserts on a
  downloaded file.
- The `api2.cursor.sh` stable-channel drift tripwire: with no pin there is nothing to drift, and
  the failure modes it covered (a moved channel, an unresolvable channel) are now covered by the
  signature check and the resolve guard.

## Tasks

1. Rewrite the Grok Bot block in `scripts.yml` as specified above, keeping its position, the
   vendor-repo disable, the sandbox note, and the trailing assertions.
2. Rewrite `tests/check-grok-bot-install.sh` for the new mechanism, including the negative
   assertions that keep the retired pin and tripwire from coming back.
3. Update `AGENTS.md`'s Grok Bot clause and `docs/layer-optimization.md`'s Grok Bot sentences;
   re-stamp the frozen doc with `doc-contract stamp`.
4. Run the full suite and the doc gate; record the evidence here.
5. Push and confirm the build passes the `script` module and completes.

## Verify

**Exit evidence (2026-10-31).** The extracted block was run end to end in a throwaway `fedora:44`
container (`BLOCK-RC=0`): it resolved `0.78.1-1`, installed `grok-bot 0.78.1-1 x86_64`, left the
vendor repo at `enabled=0`, removed the build-time repo file and key file, and left exactly one
`gpg-pubkey-380ff4bc…` entry in the rpmdb; `/usr/bin/grok-bot` and the desktop entry are present.
`bash -n` is clean on the block and on the whole snippet, and `yamllint` reports no syntax errors on
`scripts.yml` — a YAML-level mistake was caught and fixed here (the heredoc body had been written at
column 0, which terminated the block scalar).

The four negative assertions were mutation-tested, each restored afterwards: adding
`--nogpgcheck`, setting `repo_gpgcheck=0`, reintroducing a `grok-bot-0.78.1-1` version literal, and
pointing the key URL at the unsigned `grokbot/stable/…` artifact all fail
`tests/check-grok-bot-install.sh`. The suite is 10/10 green and `doc-contract check --repo-root .
--offline` reports 0 errors and no new warnings; `docs/layer-optimization.md` was edited and
re-stamped (`self_hash` 50b7e897418a1f6d → ec7096e1c2eaede0).

Mechanism proven before the block was written, in the same throwaway container:

- `dnf5 install -y grok-bot` from a repo defined with `gpgcheck=1`, `repo_gpgcheck=1` and
  `gpgkey=file://<verified key>` installed `grok-bot 0.78.1-1 x86_64`; `/usr/bin/grok-bot` and
  `/usr/share/applications/grok-bot.desktop` present; the `%post`-written
  `/etc/yum.repos.d/grok-bot.repo` appeared with `enabled=1` and flipped to `enabled=0` with the
  existing `sed`.
- **Enforcement, by negative test:** the same install against a `gpgkey=` that does not sign the
  repo fails with `Transaction failed: Signature verification failed. … Import of the key didn't
  help, wrong key?` and leaves nothing installed. With `repo_gpgcheck=1` and a wrong key,
  `repoquery` loads the repo but yields no package — which is why the block carries the shape
  guard instead of trusting a non-empty result.
- Key identity: `rpm -q gpg-pubkey` lists
  `gpg-pubkey-380ff4bcdc34a4bd92a3565342a1772e62e492d6-…` after dnf's import, so the fingerprint
  assertion is meaningful. Note `rpm --import` alone does **not** satisfy dnf5's check (it keeps
  its own store, imported through `gpgkey=`), which is why the key is handed to dnf by file path
  rather than imported directly.
- Payload comparison: the repo RPM and the download-page RPM for 0.78.1 have identical
  `rpm2cpio | sha256sum` digests (`b8104a4c…`); the repo RPM carries
  `Header OpenPGP V4 RSA/SHA256 signature, key ID 42a1772e62e492d6`, the download-page one carries
  none.
- The repo publishes only `X.Y.Z-1` releases (28 versions, newest `0.78.1-1`), so
  `--latest-limit 1` cannot select a beta.

Repo-side, after the edit:

```bash
for t in tests/check-*.sh; do bash "$t"; done   # 10 files, all green
doc-contract check --repo-root . --offline      # 0 errors, no new warnings
```

Post-push: the `bluebuild` run must clear the `script` module. Runtime confirmation stays out of
scope — this change alters how the same binary reaches the image, not how it runs.
