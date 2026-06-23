#!/usr/bin/env node
// copilot-quota-api/device_oauth.js
// Simple GitHub OAuth Device Flow helper that saves the obtained access
// token into the macOS Keychain using the existing keychain helper.

const keychain = require('./keychain');
const { spawnSync } = require('child_process');
const readline = require('readline');

async function prompt(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise(resolve => rl.question(question, ans => { rl.close(); resolve(ans.trim()); }));
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function run() {
  const clientId = process.env.COPILOT_OAUTH_CLIENT_ID || process.env.GITHUB_OAUTH_CLIENT_ID || await prompt('COPILOT_OAUTH_CLIENT_ID (register an OAuth App): ');
  if (!clientId) {
    console.error('A client_id is required. Set COPILOT_OAUTH_CLIENT_ID env or provide it interactively.');
    process.exit(2);
  }

  const scope = process.env.COPILOT_OAUTH_SCOPE || 'read:user';

  console.log('Requesting device code from GitHub...');
  const params = new URLSearchParams({ client_id: clientId, scope });
  const res = await fetch('https://github.com/login/device/code', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json' },
    body: params
  });
  if (!res.ok) {
    const txt = await res.text().catch(() => '<no-body>');
    console.error('Failed to request device code:', res.status, txt);
    process.exit(3);
  }
  const data = await res.json();

  // Data contains: device_code, user_code, verification_uri, expires_in, interval, verification_uri_complete
  console.log('\nFollow these instructions to authorize:');
  if (data.verification_uri_complete) {
    console.log(`Open: ${data.verification_uri_complete}`);
    try { spawnSync('open', [data.verification_uri_complete]); } catch (e) {}
  } else {
    console.log(`Open: ${data.verification_uri}`);
    console.log(`Enter code: ${data.user_code}`);
  }
  console.log(`Code: ${data.user_code}`);
  console.log(`Expires in ${data.expires_in} seconds. Polling every ${data.interval || 5} seconds.`);

  const expiresAt = Date.now() + (data.expires_in * 1000);
  let interval = data.interval || 5;

  while (Date.now() < expiresAt) {
    await sleep(interval * 1000);
    try {
      const tokenParams = new URLSearchParams({ client_id: clientId, device_code: data.device_code, grant_type: 'urn:ietf:params:oauth:grant-type:device_code' });
      const tokRes = await fetch('https://github.com/login/oauth/access_token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json' },
        body: tokenParams
      });
      if (!tokRes.ok) {
        const txt = await tokRes.text().catch(() => '<no-body>');
        console.error('Token endpoint error:', tokRes.status, txt);
        process.exit(4);
      }
      const tok = await tokRes.json();
      if (tok.error) {
        if (tok.error === 'authorization_pending') continue;
        if (tok.error === 'slow_down') { interval += 5; continue; }
        if (tok.error === 'expired_token') { console.error('Device code expired.'); process.exit(5); }
        if (tok.error === 'access_denied') { console.error('User denied access.'); process.exit(6); }
        console.error('Unexpected token error:', tok);
        process.exit(7);
      }
      if (tok.access_token) {
        console.log('\nAccess token received.');
        const saved = keychain.setTokenInKeychain(tok.access_token);
        if (saved) {
          console.log('Saved access token to macOS Keychain.');
        } else {
          console.warn('Failed to save token to Keychain; printing it (store securely):\n', tok.access_token);
        }
        console.log('You can now run the copilot-quota-api and it will pick the token from Keychain.');
        process.exit(0);
      }
    } catch (err) {
      console.error('Error polling token endpoint:', err && err.message ? err.message : err);
      process.exit(8);
    }
  }

  console.error('Timed out waiting for user authorization.');
  process.exit(9);
}

run().catch(err => { console.error(err && err.message ? err.message : err); process.exit(1); });
