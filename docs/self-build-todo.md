# TODO: self-build the metapi image

## Why

The metapi gateway (`files/system/etc/containers/systemd/users/metapi.container`) currently
pulls a prebuilt image from a **personal Docker Hub account**:

```
docker.io/1467078763/metapi@sha256:d6118229e7d2423262b253a419baf18c22f1682a7bbc7d3c756d090aa2b295c6
```

metapi holds credentials for every upstream LLM provider account (reseller panels, the
corporate relay, direct provider keys). Trusting an unnamespaced personal image for that is a
supply-chain smell. The digest pin mitigates silent tampering (the image can't change under a
fixed digest), but it does **not** establish provenance — we never audited what's in it.

## What to do

Build metapi from source (MIT-licensed, https://github.com/cita-777/metapi) and repoint the
Quadlet unit at an image you control:

1. Clone + review the source at the revision the pinned image was built from:
   `org.opencontainers.image.revision = 41767a65ec8e5470a9a70f4615b47dc24949afff`
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
