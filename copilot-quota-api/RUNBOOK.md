## copilot-quota-api Runbook (production)

This document records operational steps, monitoring, alerts and maintenance for the copilot-quota-api service.

1) Service overview
- Polls GitHub Copilot `/copilot_internal/user` every minute and exposes `/quota`, `/health`, `/metrics` (Prometheus).
- Designed to run as a user LaunchAgent on macOS or as a system service.

2) Metrics
- `GET /metrics` exposes Prometheus metrics. Key metrics:
  - `copilot_quota_total` (gauge)
  - `copilot_quota_used` (gauge)
  - `copilot_overage_used` (gauge)
  - `copilot_fetch_failures_total` (counter)
  - `copilot_fetch_success_total` (counter)

3) Logs
- The LaunchAgent writes stdout/stderr to `~/Library/Logs` as configured by the install script.
- Logs are structured JSON (pino). Configure `LOG_LEVEL` to `info` or `warn` in production.
- Rotate logs using system tools (`newsyslog` / `logrotate`) or rely on cluster logging when running in a container.

4) Alerts (suggested)
- Alert when `copilot_fetch_failures_total` increases rapidly or `consecutiveFailures` > 5.
- Alert when `/health` returns `ok: false` for more than 5 minutes.

5) Secrets and token rotation
- Tokens are stored in macOS Keychain by default; prefer a secret manager in hosted deployments.
- Rotate tokens via your org's token workflows and update the Keychain entry or environment variable.

6) Packaging & deployment
- Build a single macOS binary with `npm run build:bin` on a macOS runner (CI or local).
- Wrap the binary into a `.app` with `scripts/package-app.sh` and create a DMG with `scripts/create-dmg.sh`.

7) Backups & disaster recovery
- Keep copies of configuration locally and in your organization's secrets manager. The service itself is ephemeral and stateless.

8) Troubleshooting
- Run `node index.js --dry-run` locally to validate environment and token.
- Use `curl -sS http://localhost:3000/health` and `/quota` to inspect current state.
