#!/usr/bin/env bash
set -euo pipefail

script="recipes/module-recipes/scripts.yml"

grep -Fq "https://bitwarden.com/download/?app=desktop&platform=linux&variant=rpm" "${script}"
grep -Fq "BITWARDEN_RPM=\"/tmp/bitwarden-desktop.rpm\"" "${script}"
grep -Fq "dnf5 install -y \"\${BITWARDEN_RPM}\"" "${script}"
