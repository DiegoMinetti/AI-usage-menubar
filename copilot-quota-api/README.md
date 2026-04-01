# copilot-quota-api

Minimal, resource-efficient Node.js service that polls GitHub Copilot quota every minute and exposes a tiny HTTP API.

Requirements
- Node.js 18+

Quick start

1. Create a GitHub token with the needed scope and set it in the environment as `GITHUB_TOKEN` (or `GITHUB_PAT`).

2. Run in dry-run (no token required):

```bash
node index.js --dry-run
```

3. Run normally (example):

```bash
GITHUB_TOKEN="<your_token>" node index.js
```

Endpoints
- `GET /quota` — returns latest parsed quota snapshot (fields: `quota`, `used`, `overageUsed`, `overageEnabled`, `resetDate`, `fetchedAt`, `stale`).
- `GET /health` — basic health JSON (ok, lastFetchTime, consecutiveFailures, uptimeMs).

Notes
- Store your secret in a secure secret manager / key vault in production. Do not put tokens into client code.
- The service uses in-memory cache and polls every minute (`POLL_INTERVAL_MS`). Tune with env vars.

macOS usage (single-command install)

1. First run interactively to store token in macOS Keychain (the app will prompt you):

```bash
node index.js
```

When prompted paste your `GITHUB_TOKEN` (or `GITHUB_PAT`). The token will be saved securely in Keychain and used by the service.

2. Install as a user LaunchAgent (auto-start):

```bash
chmod +x scripts/install-launchagent.sh
scripts/install-launchagent.sh
```

3. To stop/uninstall:

```bash
chmod +x scripts/uninstall-launchagent.sh
scripts/uninstall-launchagent.sh
```

Notes
- The LaunchAgent runs the Node script directly; ensure Node 18+ is installed and available in your `PATH`.
- If you prefer to simply run without install, `GITHUB_TOKEN="..." node index.js` works too.

Production
 - Metrics: the service exposes Prometheus metrics at `GET /metrics` (enabled by default). Use `METRICS=0` to disable.
 - Logging: structured JSON logs (pino). Control verbosity with `LOG_LEVEL` env var.
 - Packaging: build a single macOS executable with `npm run build:bin` (requires running on macOS in CI or locally). Use `scripts/package-app.sh` and `scripts/create-dmg.sh` to create a `.app` bundle and `.dmg`.
 - CI: a GitHub Actions workflow is included at `.github/workflows/ci.yml` to run tests and build macOS binaries on macOS runners.

Runbook
 - See `RUNBOOK.md` for operational guidance, alerts and troubleshooting steps.
