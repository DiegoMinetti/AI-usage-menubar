const { test } = require('node:test');
const assert = require('assert');
const { parseQuotaFromSnapshot } = require('../quotaFetcher');

test('parse simple snapshot calculates used correctly', () => {
  const json = { quota_snapshots: { chat: { entitlement: 100, percent_remaining: 50 } } };
  const parsed = parseQuotaFromSnapshot(json);
  assert.strictEqual(parsed.quota, 100);
  assert.strictEqual(parsed.used, 50);
});

test('parse reset date is converted to Date', () => {
  const json = { quota_snapshots: { chat: { entitlement: 200, percent_remaining: 75, reset_date: '2030-01-01T00:00:00Z' } } };
  const parsed = parseQuotaFromSnapshot(json);
  assert.strictEqual(parsed.resetDate.toISOString(), '2030-01-01T00:00:00.000Z');
});
