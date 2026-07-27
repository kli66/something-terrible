#!/usr/bin/env bash
set -euo pipefail

recipe="recipes/recipe.yml"
module="recipes/module-recipes/agentsview.yml"
systemd_recipe="recipes/module-recipes/systemd.yml"
service="files/system/usr/lib/systemd/user/agentsview.service"
runtime_quadlet="files/system/etc/containers/systemd/users/agentsview.container"
historical_quadlet="docs/superseded/agentsview.container"

fail() {
  echo "check-agentsview-install: $*" >&2
  exit 1
}

[[ -f "${module}" ]] || fail "missing AgentsView containerfile module"
[[ -f "${service}" ]] || fail "missing AgentsView systemd user service"

# The binary comes from the official image at an immutable digest. The release
# annotation, digest, and executable build assertion must move together.
grep -Fxq "type: containerfile" "${module}" || fail "AgentsView module is not a containerfile module"
grep -Fq "# AgentsView 0.38.1." "${module}" || fail "missing pinned version annotation"
grep -Fq "skopeo inspect --format '{{.Digest}}' docker://ghcr.io/kenn-io/agentsview:<version>" "${module}" || fail "missing version-update instructions"
grep -Fq "COPY --from=ghcr.io/kenn-io/agentsview@sha256:5111d313def68791c0b98754289d2f027e50f2fe5ea970c86ce7b68f296193b8 /usr/local/bin/agentsview /usr/bin/agentsview" "${module}" || fail "missing exact AgentsView image digest or copy path"
grep -Fq "RUN /usr/bin/agentsview --version | grep -F 0.38.1" "${module}" || fail "missing build-time executable/version assertion"

# files.yml must install the user unit before the systemd module enables it;
# the binary module must also run before systemd enablement.
files_line="$(awk '/module-recipes\/files.yml/ { print NR }' "${recipe}")"
agentsview_line="$(awk '/module-recipes\/agentsview.yml/ { print NR }' "${recipe}")"
systemd_line="$(awk '/module-recipes\/systemd.yml/ { print NR }' "${recipe}")"
[[ -n "${files_line}" && -n "${agentsview_line}" && -n "${systemd_line}" ]] || fail "missing recipe module entry"
(( files_line < agentsview_line && agentsview_line < systemd_line )) || fail "files.yml and agentsview.yml must precede systemd.yml"

# The service is loopback-only and lives strictly inside Kai's graphical login
# session. It gets Linuxbrew first for authenticated Claude/Codex Insights.
grep -Fxq "ConditionUser=kai" "${service}" || fail "service is not restricted to Kai"
grep -Fxq "Requisite=graphical-session.target" "${service}" || fail "service does not require a graphical session"
grep -Fxq "PartOf=graphical-session.target" "${service}" || fail "service does not stop with the graphical session"
grep -Fxq "WantedBy=graphical-session.target" "${service}" || fail "service is not enabled by the graphical session"
grep -Fxq "ExecStart=/usr/bin/agentsview serve --host 127.0.0.1 --port 8080 --no-browser" "${service}" || fail "unexpected AgentsView command or network binding"
grep -Fxq "Restart=on-failure" "${service}" || fail "service restart policy must be on-failure"
grep -Fxq "RestartSec=5s" "${service}" || fail "service restart delay must be 5s"
grep -Fxq "Environment=PATH=/home/linuxbrew/.linuxbrew/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "${service}" || fail "service PATH must put Linuxbrew first"
grep -Fxq "Environment=AGENTSVIEW_TELEMETRY_ENABLED=0" "${service}" || fail "anonymous telemetry is not disabled"
if grep -Eqi 'update.*(disable|enabled=0|false)|AGENTSVIEW_.*UPDATE' "${service}"; then
  fail "update notifications must remain enabled"
fi

# BlueBuild enables the packaged user unit globally; no baked wants symlink or
# linger state is needed because graphical-session.target owns its lifecycle.
awk '/^user:/{user_scope=1} user_scope&&/^[[:space:]]+enabled:/{enabled_scope=1} enabled_scope&&/-[[:space:]]+agentsview\.service/{found=1} END{exit !found}' "${systemd_recipe}" || fail "agentsview.service is not under systemd user.enabled"
[[ ! -e "${runtime_quadlet}" ]] || fail "runtime AgentsView Quadlet still exists"
[[ -f "${historical_quadlet}" ]] || fail "superseded Quadlet was not retained under docs"
grep -Fq "# HISTORICAL: superseded" "${historical_quadlet}" || fail "superseded Quadlet is not marked historical"
if find files/system -type l -name 'agentsview.service' -print -quit | grep -q .; then
  fail "manual agentsview.service wants symlink must not be source-controlled"
fi
if find files/system -path '*systemd/linger*' -o -name '*agentsview*linger*' | grep -q .; then
  fail "AgentsView linger state must not be baked into the image"
fi

# Preserve upstream per-user state and discovery, including active and archived
# Codex sessions. Do not bake config or override data/session/provider paths.
if find files/system -path '*/.agentsview/config.toml' -print -quit | grep -q .; then
  fail "per-user AgentsView config must not be baked into the image"
fi
if grep -Eq 'AGENTSVIEW_DATA_DIR|CLAUDE_PROJECTS_DIR|CODEX_SESSIONS_DIR|--(data|session)-dir|Environment=(CLAUDE|CODEX).*(_PATH|_BINARY)=' "${service}"; then
  fail "service must retain upstream data, session, and provider discovery"
fi

echo "check-agentsview-install: OK"
