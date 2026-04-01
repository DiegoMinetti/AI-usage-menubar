/* Minimal quota fetcher: no deps, uses global fetch (Node 18+)
 * Exports: fetchQuotaSnapshotWithRetry(githubToken, opts)
 *          parseQuotaFromSnapshot(json)
 */

const DEFAULT_ATTEMPTS = 5;

function ensureFetch() {
  if (typeof globalThis.fetch !== 'function') {
    throw new Error('global fetch not available. Requires Node 18+ or polyfill.');
  }
}

async function fetchQuotaSnapshotWithRetry(githubToken, opts = {}) {
  ensureFetch();
  const attempts = opts.attempts ?? DEFAULT_ATTEMPTS;
  const url = 'https://api.githubcopilot.com/copilot_internal/user';
  const headers = {
    Authorization: `token ${githubToken}`,
    'X-GitHub-Api-Version': '2025-04-01',
    Accept: 'application/json'
  };

  let attempt = 0;
  while (true) {
    try {
      const res = await fetch(url, { method: 'GET', headers });
      if (!res.ok) {
        const body = await res.text().catch(() => '<no-body>');
        throw new Error(`HTTP ${res.status}: ${body}`);
      }
      const json = await res.json();
      return json;
    } catch (err) {
      attempt++;
      if (attempt >= attempts) throw err;
      const backoff = Math.min(30000, 500 * Math.pow(2, attempt));
      const jitter = Math.random() * 200;
      await new Promise(r => setTimeout(r, backoff + jitter));
    }
  }
}

function parseQuotaFromSnapshot(json) {
  if (!json) return null;
  const snapshots = json.quota_snapshots;
  if (!snapshots) return null;
  const snapshot = snapshots.premium_interactions ?? snapshots.chat ?? snapshots.premium_models ?? snapshots.completions;
  if (!snapshot) return null;

  const entitlement = Number.parseInt(snapshot.entitlement ?? snapshot.entitlement?.toString?.() ?? '0', 10);
  const percent_remaining = Number(snapshot.percent_remaining ?? snapshot.percent_remaining ?? 0);
  const overage_count = Number(snapshot.overage_count ?? 0);
  const overage_permitted = !!snapshot.overage_permitted;
  const reset_date = snapshot.reset_date ?? json.quota_reset_date ?? null;

  const used = Math.max(0, (entitlement === -1 ? 0 : entitlement * (1 - (percent_remaining || 0) / 100)));

  return {
    quota: entitlement,
    used,
    overageUsed: overage_count,
    overageEnabled: overage_permitted,
    resetDate: reset_date ? new Date(reset_date) : null,
    rawSnapshot: snapshot
  };
}

module.exports = { fetchQuotaSnapshotWithRetry, parseQuotaFromSnapshot };
