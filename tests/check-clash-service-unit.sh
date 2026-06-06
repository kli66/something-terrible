#!/usr/bin/env bash
set -euo pipefail

script="recipes/module-recipes/scripts.yml"
systemd_recipe="recipes/module-recipes/systemd.yml"
recipe="recipes/recipe.yml"

grep -Fq "https://raw.githubusercontent.com/clash-verge-rev/clash-verge-service-ipc/main/resources/systemd_service_unit.tmpl" "${script}"
grep -Fq "CLASH_VERGE_SERVICE_EXEC_START=/usr/bin/clash-verge-service" "${script}"
grep -Fq "CLASH_VERGE_SERVICE_GROUP=1000" "${script}"
grep -Fq "clash-verge-service.service" "${script}"
grep -Fq "ExecStart=/usr/bin/clash-verge-service" "${script}"
grep -Fq "Group=1000" "${script}"
grep -Fq "enabled:" "${systemd_recipe}"
grep -Fq "clash-verge-service.service" "${systemd_recipe}"

scripts_line="$(awk '/module-recipes\/scripts.yml/ { print NR }' "${recipe}")"
systemd_line="$(awk '/module-recipes\/systemd.yml/ { print NR }' "${recipe}")"
test "${scripts_line}" -lt "${systemd_line}"
