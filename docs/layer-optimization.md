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
desktop RPM, `pass-cli/versions.json` for the CLI) and verifies the hash that same manifest names.
The rationale is **churn, not verification strength**: the layer only changes when the vendor ships a
release, so a vendor-latest channel costs no more churn than a pin. The integrity anchors differ, and
the difference is deliberate rather than an oversight. Proton Pass verifies the hash that the same
manifest names, which catches corruption, truncation, and a retargeted download but shares an origin
with the artifact, so it is not a signature. Bitwarden's redirect carries no checksum at all, so TLS
to `bitwarden.com` is its only anchor.

Size delta for the Proton Pass channel: 120,309,189 B downloaded / 390,913,189 B installed for the
desktop RPM, plus 56,367,544 B for the `pass-cli` binary (which is also the download). Together with
the proposed `add-1password` change (~147 MB downloaded / ~608 MB installed) the vendor-latest
channels cost roughly 1.05 GB installed and ~324 MB of download per cache-invalidating rebuild. That
is a stated consideration when accepting these channels, not a reason to block either change.

The module has no `no-cache: true` — these layers cache and only change on deliberate version bumps,
and a vendor-latest layer re-resolves only when it re-executes.

The *current* pins and their dates are not inventoried here — they live in
`recipes/module-recipes/scripts.yml`, in the comment next to each URL (keep the URL and its
version/date annotation in sync when bumping). `tests/check-*.sh` grep-assert the pins
(e.g. `tests/check-bettbox-install.sh`, `tests/check-agentsview-install.sh`).

**To update:** browse the GitHub releases page, copy the new RPM URL, update the comment with version/date.
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
