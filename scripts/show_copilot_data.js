#!/usr/bin/env node
// scripts/show_copilot_data.js
// Small helper to show where Copilot data comes from and to fetch it:
// - If GITHUB_TOKEN is set, calls the internal Copilot quota API via copilot-quota-api/quotaFetcher.js
// - If --profile / PLAYWRIGHT_PROFILE is provided, runs scripts/scrape_copilot.js to scrape the settings page
// Requires Node 18+ (global fetch). Playwright is required only for scraping.

const { spawnSync } = require('child_process');
const path = require('path');

async function fetchViaApi() {
  try {
    const token = process.env.GITHUB_TOKEN || process.env.GITHUB_PAT || process.env.GITHUB_OAUTH_TOKEN;
    if (!token) {
      console.log('SKIP: no GITHUB_TOKEN in environment');
      return;
    }
    console.log('\n==> Fetching quota snapshot from Copilot internal API (requires token)');
    const { fetchQuotaSnapshotWithRetry, parseQuotaFromSnapshot } = require('../copilot-quota-api/quotaFetcher');
    const raw = await fetchQuotaSnapshotWithRetry(token, { attempts: 3 });
    console.log('\nRAW snapshot JSON:\n', JSON.stringify(raw, null, 2));
    const parsed = parseQuotaFromSnapshot(raw);
    console.log('\nPARSED snapshot (normalized):\n', JSON.stringify(parsed, null, 2));
  } catch (err) {
    console.error('API fetch failed:', err && err.message ? err.message : err);
  }
}

function runScrape(profile) {
  console.log('\n==> Running HTML scraper (Playwright) to fetch https://github.com/settings/copilot');
  const script = path.resolve(__dirname, 'scrape_copilot.js');
  const args = [];
  if (profile) { args.push('--profile', profile); }
  const res = spawnSync(process.execPath, [script, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  if (res.error) {
    console.error('Failed to spawn scraper:', res.error.message);
    return;
  }
  if (res.status !== 0) {
    console.error('Scraper exited with code', res.status);
    console.error(res.stderr);
    return;
  }
  try {
    const out = JSON.parse(res.stdout.trim());
    console.log('\nSCRAPE result:\n', JSON.stringify(out, null, 2));
  } catch (e) {
    console.log('\nScraper output:\n', res.stdout);
  }
}

(async function main() {
  console.log('Show Copilot data sources and example fetches');
  // 1) API fetch (if token provided)
  await fetchViaApi();

  // 2) Scrape via Playwright if profile provided
  const argv = process.argv.slice(2);
  const profileArgIndex = argv.findIndex(a => a === '--profile' || a === '-p');
  let profile = process.env.PLAYWRIGHT_PROFILE || null;
  if (profileArgIndex !== -1 && argv[profileArgIndex + 1]) profile = argv[profileArgIndex + 1];
  if (profile) {
    runScrape(profile);
  } else {
    console.log('\nSKIP: no profile provided for scraper. Run with `--profile "/path/to/chrome/profile"` or set PLAYWRIGHT_PROFILE env var to run the scraper.');
  }

  console.log('\nDone.');
})();
