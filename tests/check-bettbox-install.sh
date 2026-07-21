#!/usr/bin/env bash
set -euo pipefail

script="recipes/module-recipes/scripts.yml"
systemd_recipe="recipes/module-recipes/systemd.yml"
recipe="recipes/recipe.yml"

grep -Fq "# Install Bettbox (pinned" "${script}"
grep -Fq "https://github.com/appshubcc/Bettbox/releases/download/" "${script}"
grep -Fq "BETTBOX_URL=" "${script}"
grep -Fq "Bettbox-1.18.6-linux-amd64.rpm" "${script}"
grep -Fq "dnf5 install -y \"\${BETTBOX_URL}\"" "${script}"
grep -Fq "chmod u+s /usr/share/Bettbox/BettboxCore" "${script}"

if grep -Fq "clash-verge-service.service" "${systemd_recipe}"; then
  echo "clash-verge-service.service should not be enabled for Bettbox" >&2
  exit 1
fi

if grep -Fq "clash-verge" "${script}"; then
  echo "Clash Verge install logic should be removed" >&2
  exit 1
fi

scripts_line="$(awk '/module-recipes\/scripts.yml/ { print NR }' "${recipe}")"
systemd_line="$(awk '/module-recipes\/systemd.yml/ { print NR }' "${recipe}")"
test "${scripts_line}" -lt "${systemd_line}"
