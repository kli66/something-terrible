---
id: pin-base-image
status: landed
persistence: ephemeral
depends_on:
files_owned:
  - docs/changes/pin-base-image/change.md
  - recipes/recipe.yml
  - tests/check-image-pin.sh
  - docs/layer-optimization.md
  - AGENTS.md
accepted_at: 2026-11-13
started_at: 2026-11-13
landed_at: 2026-11-13
archive_path: docs/changes/archive/2026-11-13-pin-base-image
---
# Pin the Fedora base image to a release tag

Status: Landed · 2026-11-13

**Exit reconciliation (2026-11-13).** All four tasks are done. The pinned tag `44.20261112.0`
resolves to `sha256:47d27b4ae8ae85316a1b8a0f82312153b552cdb21a4fe2f71f9d85e04c8514cf` (verified with
`skopeo inspect`), and the recipe comment records that digest. `bash tests/check-*.sh` is 14/14
green, including the new `tests/check-image-pin.sh`, which fails when `image-version` is set back to
`44`. `doc-contract check --repo-root . --offline` reports 0 errors / 0 new warnings, and
`docs/layer-optimization.md` was re-stamped. The base now advances only at a deliberate bump; module
order and the `signing` module are unchanged.

**Upstream dependencies:** The `quay.io/fedora-ostree-desktops/kinoite` registry publishes immutable
release tags such as `44.20261112.0`. Verified 2026-11-13: that tag resolves to
`sha256:47d27b4ae8ae85316a1b8a0f82312153b552cdb21a4fe2f71f9d85e04c8514cf`, created
2026-11-12 03:16:57Z, and its `sha256-47d27b4a….sig` signature tag is present.
**Dependents:** None in this repository.
**Files owned:** `docs/changes/pin-base-image/change.md`, `recipes/recipe.yml`,
`tests/check-image-pin.sh` (new), `docs/layer-optimization.md`, and `AGENTS.md`.

## Why

`image-version: 44` made every build follow whatever Fedora published last, so rebuilding an
unchanged recipe could silently change the base. Pinning the release tag makes each build's base a
reviewed constant; Fedora updates arrive at a deliberate bump instead of mid-review.

This supersedes the "not implemented" note in `docs/layer-optimization.md` §C. That note rejected
*DIGEST* pinning for churn reasons; the release tag is the pinned unit here, and the digest is
recorded beside it for audit.

## What changes

### Δ ADDED

- `tests/check-image-pin.sh`: asserts the base image and that `image-version` is a full Fedora
  release tag (`<major>.<YYYYMMDD>.<n>`), not the floating major or a moving tag.

### Δ MODIFIED

- `recipes/recipe.yml`: `image-version: 44` → `44.20261112.0`, with the tag's digest and the bump
  procedure in a comment.
- `docs/layer-optimization.md` §C: records the release-tag pin, its update cost, and why digest
  pinning remains rejected.
- `AGENTS.md`: the base pin rule and the test count (13 → 14).

### Δ REMOVED

- The floating `44` base tag and the automatic base updates it carried.

## Tasks

1. Create this change and its roadmap entry.
2. Pin the recipe and add the test.
3. Update the frozen doc and `AGENTS.md`; stamp the frozen doc.
4. Run the suite and the doc gate, then land.

## Verify

- `bash tests/check-image-pin.sh` passes, and fails when `image-version` is set back to `44`.
- `bash tests/check-*.sh` is 14/14 green.
- `doc-contract check --repo-root . --offline` is green.
- `skopeo inspect` resolves the pinned tag and the recorded digest matches.
- Invariant spot-check: module order and the `signing` module are unchanged.

## Out of scope

- Pinning by digest.
- Moving to Fedora 45.
- Any Tern install definition; the vendor's build service remains private.
