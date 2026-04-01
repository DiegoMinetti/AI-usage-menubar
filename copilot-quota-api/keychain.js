const { spawnSync } = require('child_process');

const SERVICE = 'copilot-quota-api';

function isMac() {
  return process.platform === 'darwin';
}

function getTokenFromKeychain() {
  if (!isMac()) return null;
  try {
    const r = spawnSync('security', ['find-generic-password', '-s', SERVICE, '-w'], { encoding: 'utf8' });
    if (r.status === 0) {
      return (r.stdout || '').toString().trim() || null;
    }
    return null;
  } catch (err) {
    return null;
  }
}

function setTokenInKeychain(token) {
  if (!isMac()) return false;
  try {
    // -U to update if exists
    const r = spawnSync('security', ['add-generic-password', '-a', SERVICE, '-s', SERVICE, '-w', token, '-U'], { encoding: 'utf8' });
    return r.status === 0;
  } catch (err) {
    return false;
  }
}

function deleteTokenFromKeychain() {
  if (!isMac()) return false;
  try {
    const r = spawnSync('security', ['delete-generic-password', '-s', SERVICE], { encoding: 'utf8' });
    return r.status === 0;
  } catch (err) {
    return false;
  }
}

module.exports = { isMac, getTokenFromKeychain, setTokenInKeychain, deleteTokenFromKeychain };
