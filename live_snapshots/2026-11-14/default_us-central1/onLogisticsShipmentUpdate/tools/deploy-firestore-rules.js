#!/usr/bin/env node
/**
 * Firestore rules deploy.
 * 1) service-account.json (functions/) — tavsiya etiladi
 * 2) gcloud auth print-access-token — zaxira
 *
 * Usage: node functions/tools/deploy-firestore-rules.js
 * SSL muammosi bo'lsa: node --use-system-ca functions/tools/deploy-firestore-rules.js
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const projectId = 'master-taxi-gurlan';
const rulesPath = path.join(__dirname, '..', '..', 'firestore.rules');
const keyPath = path.join(__dirname, '..', 'service-account.json');
const rules = fs.readFileSync(rulesPath, 'utf8');

async function getToken() {
  if (fs.existsSync(keyPath)) {
    const { GoogleAuth } = require('google-auth-library');
    const auth = new GoogleAuth({
      keyFile: keyPath,
      scopes: ['https://www.googleapis.com/auth/cloud-platform'],
    });
    const client = await auth.getClient();
    const res = await client.getAccessToken();
    if (res.token) return res.token;
  }
  return execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
}

async function api(method, url, body, token) {
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${res.status} ${text}`);
  }
  return text ? JSON.parse(text) : {};
}

(async () => {
  const token = await getToken();
  console.log('Creating ruleset...');
  const ruleset = await api(
    'POST',
    `https://firebaserules.googleapis.com/v1/projects/${projectId}/rulesets`,
    { source: { files: [{ name: 'firestore.rules', content: rules }] } },
    token,
  );
  console.log('Ruleset:', ruleset.name);

  console.log('Publishing release cloud.firestore...');
  const release = await api(
    'PATCH',
    `https://firebaserules.googleapis.com/v1/projects/${projectId}/releases/cloud.firestore`,
    {
      release: {
        name: `projects/${projectId}/releases/cloud.firestore`,
        rulesetName: ruleset.name,
      },
      updateMask: 'rulesetName',
    },
    token,
  );
  console.log('Release OK:', release.name || 'cloud.firestore');
})().catch((e) => {
  console.error('Deploy failed:', e.message || e);
  process.exit(1);
});
