#!/usr/bin/env bash
set -euo pipefail

script="recipes/module-recipes/bitwarden.yml"

[[ -f "${script}" ]] || { echo "check-bitwarden-install: missing ${script}" >&2; exit 1; }

grep -Fq "# Install Bitwarden Desktop (vendor redirects" "${script}"
grep -Fq "https://bitwarden.com/download/?app=desktop&platform=linux&variant=rpm" "${script}"
grep -Fq "BITWARDEN_RPM=\"/tmp/bitwarden-desktop.rpm\"" "${script}"
grep -Fq "dnf5 install -y \"\${BITWARDEN_RPM}\"" "${script}"
grep -Fq "# Last validated 2026-11-09" "${script}"
