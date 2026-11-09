---
persistence: frozen
self_hash: b3ba02ef56b5eb41
---
# Layer optimization

## Problem

Pre-optimization, the image showed:
- **270 layers, 5.55 GB total** (base Kinoite 44 is already 257 layers / 3.1 GB)
- **109 derived layers / 3.44 GB** on top of base
- **~71 layers / 2.6 GB re-downloaded** on every build, even for trivial changes (e.g., a single quadlet edit)

The root cause: **no rechunking** → timestamp churn + unstable layer boundaries → massive digest churn build-to-build.

## Solution

### A. Enable rechunk (dominant fix)

Set `rechunk: true` in `.github/workflows/build.yml` (blue-build/github-action@v1.13).

**What rechunk does:**
- **Timestamp clamping:** fixes file mtimes so identical content → identical digest
- **Stable layer plan:** reuses the prior build's OSTree-hash→layer mapping (embedded in the previous image manifest)
- **Package-group stability:** things that update together (e.g., KDE) stay in the same layer; unchanged groups keep their digest across builds

**Result:** a quadlet-only change should pull tens of MB, not gigabytes.

**Cost:** ~2–4 min extra build time, requires sudo in CI, slightly larger total image size (rechunked layers trade storage efficiency for pull efficiency).

### B. Pin vendored RPMs; vendor-latest is a named exception, not the default

Replaced `curl … releases/latest` scraping with explicitly pinned release RPM URLs in `scripts.yml`
(Bettbox, CC Switch, Chipmunk). Accepted vendor-latest channels, in landing order: **Bitwarden**,
which installs from a vendor download redirect, then **Proton Pass**, which resolves both of its
artifacts from Proton's own JSON channel manifests (`PassDesktop/linux/x64/version.json` for the
desktop RPM, `pass-cli/versions.json` for the CLI) and verifies the hash that same manifest names,
and then **Grok Bot**, which installs from the vendor's OpenPGP-signed yum repo and lets dnf verify
`repomd.xml` and each RPM against a signing key pinned by a committed sha256.
The rationale is **churn, not verification strength**: the layer only changes when the vendor ships a
release, so a vendor-latest channel costs no more churn than a pin. The integrity anchors differ, and
the difference is deliberate rather than an oversight. Proton Pass verifies the hash that the same
manifest names, which catches corruption, truncation, and a retargeted download but shares an origin
with the artifact, so it is not a signature. Bitwarden's redirect carries no checksum at all, so TLS
to `bitwarden.com` is its only anchor. Grok Bot used to be the weakest of the three: its download
page publishes neither a manifest nor a checksum and serves an unsigned RPM (`rpm -Kv` reports digests
only), so its pin carried a maintainer-computed sha256, which catches a truncated, corrupted, or
retargeted download but is neither vendor-published nor a signature. That is no longer the channel.
The vendor's signed yum repo now serves the same builds as the download page (0.78.1-1 on 2026-10-31
with an identical payload digest, differing only by the signature header), so Grok Bot moved to it:
the committed sha256 now pins the vendor's *signing key*, which dnf then uses to verify `repomd.xml`
and every RPM. A rotated key fails the hash, a forged repo or artifact fails the signature check, and
a repo that cannot be verified resolves to nothing and fails the block's shape guard. The earlier
stable-channel tripwire (`api2.cursor.sh/updates/download/stable/…` → `302`) retired with the pin it
guarded: there is no pinned artifact left to go stale.

Size delta for the Proton Pass channel: 120,309,189 B downloaded / 390,913,189 B installed for the
desktop RPM, plus 56,367,544 B for the `pass-cli` binary (which is also the download): roughly
447,280,733 B installed and 176,676,733 B downloaded per cache-invalidating rebuild. That is a stated
consideration when accepting this channel, not a reason to block it.

The module has no `no-cache: true` — these layers cache and only change on deliberate version bumps,
and a vendor-latest layer re-resolves only when it re-executes.

The *current* pins and their dates are not inventoried here — they live in
`recipes/module-recipes/scripts.yml`, in the comment next to each URL (keep the URL and its
version/date annotation in sync when bumping). `tests/check-*.sh` grep-assert the pins
(e.g. `tests/check-bettbox-install.sh`, `tests/check-agentsview-install.sh`).

**To update:** browse the GitHub releases page, copy the new RPM URL, recompute the sha256 where the
block pins one, and update the comment with version/date. Grok Bot needs nothing here — it resolves
from its signed repo — unless the vendor rotates its signing key, in which case the key hash and
fingerprint in that block, and its `Last validated` annotation, are refreshed together.
For a vendor-latest block there is nothing to edit until its resolution is re-checked; refresh that
block's `Last validated <date>` annotation when it is, and re-run its `tests/check-*.sh`.

### C. Base digest pinning (not implemented)

Initially considered pinning `base-image` by digest (like metapi/agentsview). **Skipped** because rechunk's package-group stability already handles base drift gracefully — unchanged Fedora packages (e.g., KDE) keep their digest even when the base bumps, so you inherit security updates without forced re-downloads.

## Verification

After the next build with these changes:
1. Note the layer count and total size (should stay ~270 / 5.5 GB — rechunk doesn't shrink the absolute size, it stabilizes digests).
2. Make a trivial change (e.g., edit a comment in `systemd.yml`), push, wait for the build.
3. Compare layer digests between the two builds — expect < 10 changed layers and < 100 MB re-pull for the trivial change.

The honest test: `rpm-ostree upgrade` from a machine on the prior build → the pull size tells you how much churn you've actually eliminated.

## Update 2026-11-09 — per-vendor script modules

`scripts.yml` was split into one `script` module per vendored app (`bettbox.yml`, `bitwarden.yml`,
`cc-switch.yml`, `chipmunk.yml`, `grok-bot.yml`, `proton-pass.yml`, plus `terra.yml` for the repo
block), so the two `scripts.yml` paths in section B describe the module as it was when this analysis
was written. The rationale is unchanged, and the cache argument gets stronger: a `script` module's
snippets share one layer, so one pin bump used to invalidate every vendor artifact (Proton Pass
alone is ~177 MB downloaded / ~447 MB installed per re-execution). Per-vendor modules invalidate
only the bumped vendor's layer; the cost is six additional derived layers, which rechunk's stable
layer plan and the ~109-derived-layer baseline absorb. The pins and their `Last validated`
annotations now live in each app's module; `tests/check-<app>-install.sh` asserts each.
