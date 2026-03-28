#!/usr/bin/env node
// Playwright script to scrape GitHub Copilot settings page using an existing logged-in profile.
// Usage:
//   node scripts/scrape_copilot.js --profile "/path/to/chrome/profile"
// Or set environment variable PLAYWRIGHT_PROFILE to the profile path.

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

function parseArgs() {
  const args = process.argv.slice(2);
  let profile;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--profile' || a === '-p') {
      profile = args[i + 1];
      break;
    }
    if (!a.startsWith('-') && !profile) {
      profile = a;
    }
  }
  profile = profile || process.env.PLAYWRIGHT_PROFILE;
  return { profile };
}

function normalizePercentageString(raw) {
  if (!raw) return null;
  let s = raw.replace(/,/g, '').replace(/%/g, '').trim();
  if (s.length === 0) return null;
  const v = Number(s);
  if (Number.isFinite(v)) return Math.max(0, Math.min(100, v));
  return null;
}

function parseHtml(html) {
  // Find reset date first
  const resetRegex = /Allowance resets\s*([A-Za-z]+\s+\d{1,2},\s*\d{4})/i;
  const resetMatch = resetRegex.exec(html);
  let resetDate = null;
  if (resetMatch) {
    const dateStr = resetMatch[1].trim();
    const d = new Date(dateStr);
    if (!Number.isNaN(d.getTime())) resetDate = d;
  }

  // Find all percentage occurrences
  const percentRegex = /([0-9]{1,3}(?:\.[0-9]+)?)\s*%/g;
  let matches = [];
  let m;
  while ((m = percentRegex.exec(html)) !== null) {
    matches.push({ raw: m[0], val: m[1], index: m.index, length: m[0].length });
  }

  let percentage = null;
  if (resetMatch && matches.length > 0) {
    const datePos = resetMatch.index;
    // choose last match that ends before datePos
    let chosen = null;
    for (const mm of matches) {
      if (mm.index + mm.length <= datePos) chosen = mm;
    }
    if (!chosen) chosen = matches[0];
    percentage = normalizePercentageString(chosen.val);
  } else if (matches.length > 0) {
    percentage = normalizePercentageString(matches[0].val);
  }

  return { percentage, resetDate: resetDate ? resetDate.toISOString() : null };
}

(async () => {
  const { profile } = parseArgs();
  if (!profile) {
    console.error('ERROR: profile path required. Usage: node scripts/scrape_copilot.js --profile "/path/to/profile"');
    process.exit(2);
  }

  // Ensure profile path exists
  if (!fs.existsSync(profile)) {
    console.error('ERROR: profile path not found: ' + profile);
    process.exit(3);
  }

  const url = 'https://github.com/settings/copilot';

  let context;
  try {
    context = await chromium.launchPersistentContext(profile, { headless: true });
  } catch (err) {
    console.error('ERROR: failed to launch persistent context:', err.message || err);
    process.exit(4);
  }

  try {
    const page = await context.newPage();
    await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
    // Extra wait for dynamic content
    await page.waitForTimeout(1000);

    const html = await page.content();

    const result = parseHtml(html);

    // Output JSON to stdout
    const out = { percentage: result.percentage === null ? null : Number(result.percentage), resetDate: result.resetDate };
    console.log(JSON.stringify(out));

    await context.close();
    process.exit(0);
  } catch (err) {
    console.error('ERROR: failed to scrape page:', err.message || err);
    if (context) await context.close();
    process.exit(5);
  }
})();
