# AGENTS.md

This file provides guidance to LLM agents when working with code in this repository.

## What this is

A [BlueBuild](https://blue-build.org/) recipe that builds a personal, signed Fedora **Kinoite 44** (atomic/ostree) OS image, published to `ghcr.io/kli66/something-terrible`. There is no application code — the "source" is declarative YAML describing packages, fonts, files, kernel args, and systemd state baked into the image at build time. The desktop is a **niri** (Wayland) + KDE-portal setup with `greetd`/`tuigreet` login and `fcitx5`/rime input.

## Build & test

- **Building is done by CI, not locally.** Every push (except `**.md`-only changes) triggers `.github/workflows/build.yml`, which delegates the entire build to the `blue-build/github-action`. Pushing is the build.
- **Local image build** (only if BlueBuild CLI is installed): `bluebuild build ./recipes/recipe.yml`. Most edits are validated faster by reading the schema and running the tests below.
- **Tests** are plain bash assertions that grep the recipe YAML — they verify *intent* (a package/snippet is present and ordered correctly), not a built image. Run the whole suite (7 files):
  ```bash
  for t in tests/check-*.sh; do bash "$t"; done
  ```
  (e.g. `tests/check-bettbox-install.sh`, `tests/check-bitwarden-install.sh` — one per vendored/systemd feature). When you change install logic in `scripts.yml`/`systemd.yml`, update or add a matching `tests/check-*.sh` and run it.

## Architecture

`recipes/recipe.yml` is the entrypoint. It sets `base-image`/`image-version` and pulls in ordered module files via `from-file`. **Module order matters** — modules run top-to-bottom during the build, and a test enforces that `scripts.yml` runs before `systemd.yml`. The `signing` module (cosign/Sigstore) is last.

Each `recipes/module-recipes/*.yml` is one BlueBuild module:

- **`dnf.yml`** — RPMs from Fedora, RPMFusion (`nonfree`), and COPR (`scottames/ghostty`, `avengemedia/dms`). `group-install` pulls `@multimedia` + `@development-tools`. The `exclude` list (e.g. `alacritty`, `waybar`, `fuzzel`) actively *removes* packages. This is the canonical place for repo-available packages.
- **`scripts.yml`** — escape hatch for software **not** in any repo. Each snippet runs `set -oue pipefail` and uses `dnf5 install`. Three patterns in use: (1) explicitly pinned GitHub release RPM URLs (Bettbox, CC Switch, Chipmunk) with a version/date annotation comment next to each URL — the layers cache and only change on a deliberate bump; (2) a vendor redirect URL for Bitwarden; (3) the terra-repo block, which enables the repo, installs, then disables it again so it doesn't persist in the image. When bumping a pin, update the RPM URL and its version/date annotation comment together.
- **`files.yml`** — copies `files/system/` onto the image root (`/`). So `files/system/etc/greetd/config.toml` lands at `/etc/greetd/config.toml`. Add baked-in config here.
- **`systemd.yml`** — declares `enabled`/`disabled`/`masked` units (e.g. enables `greetd`, disables `plasmalogin`, masks `systemd-remount-fs` to avoid a known Atomic 42+ boot failure).
- **`fonts.yml`** — nerd-fonts + google-fonts (heavy CJK Noto coverage).
- **`kargs.yml`** — kernel arguments (btrfs zstd compression, `noatime`; amdgpu PSR/DMUB suspend-freeze workaround). Before adding or changing a karg, check `docs/hardware-notes.md` — it has target-hardware diagnostics and general rpm-ostree kargs persistence/stability caveats.
- **`brew.yml`** — enables Homebrew on the image.

`files/scripts/example.sh` is upstream template boilerplate, not wired into the build.

## Conventions

- **Add a package the right layer:** in a repo → `dnf.yml` `install`; needs a third-party repo/RPM URL → a snippet in `scripts.yml`; a config file → `files/system/...` via `files.yml`; a service toggle → `systemd.yml`.
- When asked to add a package while running from a Fedora Linux system, first verify local Fedora repository availability with `dnf5 search <package>` or `dnf5 repoquery --info <package> --cacheonly` before deciding whether it belongs in `dnf.yml` or `scripts.yml`.
- **In `scripts.yml`**, always: install with `dnf5`, clean up temp files, and leave any temporarily-enabled repo disabled. End the module with `dnf5 clean all`. The RPM URLs are pinned constants (nothing is resolved at build time), so verify that a new URL resolves when bumping and keep each URL and its version/date annotation comment in sync.
- **The image is the README's identity** — `README.md` is still largely the upstream BlueBuild template; don't treat it as authoritative about this specific image.
- Comments in the YAML explain *why* (workarounds, bug links). Preserve them when editing nearby lines.
