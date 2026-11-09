---
persistence: deferred
---

# TODO: self-build the metapi image

## Why

The metapi gateway (`files/system/etc/containers/systemd/users/metapi.container`) currently
pulls a prebuilt image from a **personal Docker Hub account**:

```
docker.io/1467078763/metapi@sha256:42577a28ced1c6d6696499dd4969b2bd5fd039317416e4ec5077eff28e10915f
```

metapi holds credentials for every upstream LLM provider account (reseller panels, the
corporate relay, direct provider keys). Trusting an unnamespaced personal image for that is a
supply-chain smell. The digest pin mitigates silent tampering (the image can't change under a
fixed digest), but it does **not** establish provenance — we never audited what's in it. Note
that every interim bump (like the one that moved the pin to this digest) adopts a fresh,
unaudited personal build; the revision below is exactly what step 1 is meant to review.

## What to do

Build metapi from source (MIT-licensed, https://github.com/cita-777/metapi) and repoint the
Quadlet unit at an image you control:

1. Clone + review the source at the revision the pinned image was built from:
   `org.opencontainers.image.revision = 88634b0d7207039e8d0c0d026c38870cf74bf2bc`
   (skim the upstream-account adapters and credential-handling paths especially).
2. `docker build` / `podman build` the image yourself.
3. Push to a registry you own (e.g. `ghcr.io/kli66/metapi`) — the same publish path this image
   already uses (`ghcr.io/kli66/something-terrible`).
4. Update `Image=` in `metapi.container` to your digest-pinned build, and drop the
   `TODO(kai)` comment.

## Bumping the pin (interim, until self-build)

```bash
skopeo inspect docker://docker.io/1467078763/metapi:latest   # read new digest + build date
# then update the Image=...@sha256:... line and re-run tests/check-metapi-install.sh
```

## Tern (terminal) — bake once its builds are public

### Why

Tern is installed per-user on the host, not by this image. It cannot be a recipe yet: the vendor's
build service keeps the product private — `GET https://build.stencil.so/api/products` returns
`{"id":"tern","public":false,"access":false,"latest":null}`, and
`GET https://build.stencil.so/api/products/tern/builds` returns `{"error":"unauthenticated"}`
without a Stencil beta account. A CI build has no such account, and baking a beta-gated artifact
into a public image would redistribute it outside its channel.

Version state on 2026-11-09: the host's Tern updater resolved latest to **0.9.13** (commit
`8c6dfbd`, built 2026-11-08T17:27:41Z) while the installed build is **0.9.9** (commit `9c1c09f`);
0.9.13 is downloaded and staged under `~/.cache/tern/updates/`, waiting for `tern restart`.

### What to do

1. When the product becomes public, add `recipes/module-recipes/tern.yml` (pinned URL + checksum,
   `tests/check-tern-install.sh`) and an entry in `recipes/recipe.yml` before `systemd.yml`.
2. Until then, Tern stays a per-user host install; do not add a module that calls the private API
   or vendors the binary.

### Trigger

`https://build.stencil.so/api/products` reports the `tern` product with `"public": true` and a
non-null `latest`, or the vendor publishes an installer/download that resolves without a Stencil
account.
