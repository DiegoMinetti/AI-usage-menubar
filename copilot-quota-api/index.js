/*
 * copilot-quota-api - minimal, production-ready Node.js service
 * Requirements: Node 18+ (global fetch)
 *
 * Adds: Prometheus metrics, structured logging (pino), basic env validation,
 * tests, CI packaging helpers and runbook.
 */

const http = require('http');
const readline = require('readline');
const { fetchQuotaSnapshotWithRetry, parseQuotaFromSnapshot } = require('./quotaFetcher');
const keychain = require('./keychain');
const pino = require('pino');
const client = require('prom-client');

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });

const PORT = parseInt(process.env.PORT || '3000', 10);
const POLL_INTERVAL_MS = parseInt(process.env.POLL_INTERVAL_MS || '60000', 10);
const MAX_RETRY_ATTEMPTS = parseInt(process.env.MAX_RETRY_ATTEMPTS || '5', 10);
const METRICS_ENABLED = (process.env.METRICS ?? '1') !== '0';

// Token resolution: env var preferred, else Keychain on macOS
function resolveToken() {
  return process.env.GITHUB_TOKEN || process.env.GITHUB_PAT || process.env.GITHUB_OAUTH_TOKEN || keychain.getTokenFromKeychain();
}

let GITHUB_TOKEN = resolveToken();

let lastSnapshot = null;
let lastFetchTime = null;
let lastFetchOk = false;
let consecutiveFailures = 0;
let shuttingDown = false;

// Prometheus metrics
if (METRICS_ENABLED) {
  try {
    client.collectDefaultMetrics({ timeout: 5000 });
  } catch (e) {
    logger.warn('prom-client default metrics failed to register', e && e.message);
  }
}

const quotaGauge = new client.Gauge({ name: 'copilot_quota_total', help: 'Copilot entitlement' });
const usedGauge = new client.Gauge({ name: 'copilot_quota_used', help: 'Used quota' });
const overageGauge = new client.Gauge({ name: 'copilot_overage_used', help: 'Overage used' });
const fetchFailures = new client.Counter({ name: 'copilot_fetch_failures_total', help: 'Fetch failures' });
const fetchSuccesses = new client.Counter({ name: 'copilot_fetch_success_total', help: 'Fetch successes' });
const scrapeCounter = new client.Counter({ name: 'copilot_metrics_scrapes_total', help: 'Metrics scrapes' });

async function updateSnapshot(force = false) {
  if (!GITHUB_TOKEN) {
    logger.warn('No GITHUB_TOKEN available. Skipping fetch.');
    return;
  }
  try {
    const json = await fetchQuotaSnapshotWithRetry(GITHUB_TOKEN, { attempts: MAX_RETRY_ATTEMPTS });
    const parsed = parseQuotaFromSnapshot(json);
    if (!parsed) throw new Error('No quota snapshot found in response');
    if (!parsed.resetDate) parsed.resetDate = new Date(Date.now() + 30 * 24 * 3600 * 1000);
    lastSnapshot = { ...parsed, fetchedAt: new Date().toISOString() };
    lastFetchTime = Date.now();
    lastFetchOk = true;
    consecutiveFailures = 0;
    fetchSuccesses.inc();
    // update metrics
    if (METRICS_ENABLED) {
      if (typeof lastSnapshot.quota === 'number') quotaGauge.set(lastSnapshot.quota);
      if (typeof lastSnapshot.used === 'number') usedGauge.set(lastSnapshot.used);
      if (typeof lastSnapshot.overageUsed === 'number') overageGauge.set(lastSnapshot.overageUsed);
    }
    logger.info({ quota: lastSnapshot.quota, used: lastSnapshot.used }, 'quota updated');
  } catch (err) {
    lastFetchOk = false;
    consecutiveFailures++;
    fetchFailures.inc();
    logger.warn({ err: err && err.message }, 'quota fetch failed');
  }
}

function schedulePoll() {
  // initial jittered start
  setTimeout(() => updateSnapshot().catch(err => logger.error(err)), 1000 + Math.random() * 1000);
  setInterval(() => updateSnapshot().catch(err => logger.error(err)), POLL_INTERVAL_MS);
}

function createServer() {
  return http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/quota') {
      const payload = lastSnapshot ? { ...lastSnapshot, stale: !lastFetchOk, consecutiveFailures } : { error: 'no_data', stale: true };
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify(payload));
    }

    if (req.method === 'GET' && req.url === '/health') {
      const health = {
        ok: lastFetchOk || false,
        lastFetchTime: lastFetchTime ? new Date(lastFetchTime).toISOString() : null,
        consecutiveFailures,
        uptimeMs: Math.floor(process.uptime() * 1000),
      };
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify(health));
    }

    if (METRICS_ENABLED && req.method === 'GET' && req.url === '/metrics') {
      scrapeCounter.inc();
      // prom-client register.metrics() may be async in some versions
      Promise.resolve(client.register.metrics())
        .then(metrics => {
          res.writeHead(200, { 'Content-Type': 'text/plain; version=0.0.4; charset=utf-8' });
          res.end(metrics);
        })
        .catch(err => {
          res.writeHead(500, { 'Content-Type': 'text/plain' });
          res.end('error');
        });
      return;
    }

    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found');
  });
}

function onSig() {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info('Shutting down...');
  process.exit(0);
}

async function promptForTokenAndMaybeSave() {
  if (!process.stdin.isTTY) return;
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const question = (q) => new Promise(res => rl.question(q, ans => res(ans.trim())));
  try {
    const token = await question('No Copilot token found. Paste GitHub token (will be saved to macOS Keychain) or empty to cancel: ');
    if (!token) {
      logger.warn('No token provided; exiting.');
      process.exit(1);
    }
    const saved = keychain.isMac() ? keychain.setTokenInKeychain(token) : false;
    if (saved) logger.info('Token saved to macOS Keychain.');
    else if (keychain.isMac()) logger.warn('Failed to save token to Keychain; continuing with in-memory token.');
    GITHUB_TOKEN = token;
  } finally {
    rl.close();
  }
}

if (process.argv.includes('--dry-run') || process.argv.includes('-d')) {
  logger.info('DRY RUN: verifying environment and script startup');
  if (!GITHUB_TOKEN) {
    logger.warn('DRY RUN: no GITHUB_TOKEN available. Exiting 0 (syntax OK).');
    process.exit(0);
  } else {
    (async () => {
      await updateSnapshot(true);
      logger.info('DRY RUN: fetched snapshot:', lastSnapshot);
      process.exit(lastFetchOk ? 0 : 1);
    })().catch(err => { logger.error(err); process.exit(1); });
  }
} else {
  (async () => {
    if (!GITHUB_TOKEN) {
      // attempt interactive prompt on first run
      await promptForTokenAndMaybeSave();
    }
    const server = createServer();
    server.listen(PORT, () => {
      logger.info(`copilot-quota-api listening on port ${PORT}`);
    });
    schedulePoll();
    process.on('SIGINT', onSig);
    process.on('SIGTERM', onSig);
  })();
}

module.exports = { updateSnapshot };
