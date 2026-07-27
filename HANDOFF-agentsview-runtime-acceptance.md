# AgentsView runtime acceptance

This check must be performed on the newly built and booted image. Repository validation alone does not prove that the binary, user service, CLI authentication, session discovery, or Insights work at runtime.

## Prerequisites

1. Push the branch.
2. Confirm the BlueBuild CI build passed.
3. Rebase onto the newly published image and reboot.
4. Log in as `kai` to the graphical niri session.

## Command checks

Run:

```bash
/usr/bin/agentsview --version
systemctl --user is-enabled agentsview.service
systemctl --user is-active agentsview.service
systemctl --user show agentsview.service \
  -p FragmentPath -p Environment -p MainPID -p NRestarts
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/
ss -ltnp | rg '127\.0\.0\.1:8080'
test ! -e /etc/containers/systemd/users/agentsview.container
podman ps --filter name=agentsview --format '{{.Names}}'
```

Pass criteria:

- Version reports `0.38.1`.
- The unit is `enabled` and `active`.
- `FragmentPath` is `/usr/lib/systemd/user/agentsview.service`.
- The service environment has Linuxbrew first in `PATH` and `AGENTSVIEW_TELEMETRY_ENABLED=0`.
- `MainPID` is non-zero and `NRestarts` is not increasing.
- The HTTP request returns `200`.
- The listener is only on `127.0.0.1:8080`.
- The old runtime Quadlet is absent.
- The `podman ps` command prints nothing for AgentsView.

## UI checks

Open `http://127.0.0.1:8080` and verify:

1. One known Claude session is visible.
2. One active Codex session is visible.
3. One archived Codex session is visible.
4. Generate one Claude Insight and one Codex Insight. Both must finish without CLI-not-found, `PATH`, authentication, or network errors.
5. Run `systemctl --user restart agentsview.service`, reload the UI, and confirm both generated Insights remain visible.
6. Leave the service idle for at least 25 minutes, then run:

   ```bash
   systemctl --user show agentsview.service -p ActiveState -p NRestarts
   ```

   It must remain active without a restart loop.

## If anything fails

Capture the failed command and its complete output, plus:

```bash
systemctl --user status agentsview.service --no-pager
journalctl --user -u agentsview.service -b --no-pager
```

Report those outputs and the failed UI step back for diagnosis. Runtime acceptance is complete only when every command and UI check above passes.
