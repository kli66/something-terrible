#!/usr/bin/env bash
set -euo pipefail

recipe="recipes/recipe.yml"

fail() {
  echo "check-image-pin: $*" >&2
  exit 1
}

[[ -f "${recipe}" ]] || fail "missing ${recipe}"

grep -Fq "base-image: quay.io/fedora-ostree-desktops/kinoite" "${recipe}" \
  || fail "unexpected base-image"

version="$(awk '/^image-version:[[:space:]]/ { sub(/^image-version:[[:space:]]*/, ""); print; exit }' "${recipe}")"
[[ -n "${version}" ]] || fail "missing image-version"

# A pinned Fedora release tag (44.20261112.0), not the floating major 44 or a moving tag.
[[ "${version}" =~ ^[0-9]+\.[0-9]{8}\.[0-9]+$ ]] \
  || fail "image-version '${version}' is not a pinned Fedora release tag"

echo "check-image-pin: OK"
