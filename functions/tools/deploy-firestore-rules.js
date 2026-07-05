#!/usr/bin/env node
/**
 * Firestore rules deploy (firebase login bo'lmasa ham gcloud token bilan).
 * Usage: node functions/tools/deploy-firestore-rules.js
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const projectId = 'master-taxi-gurlan';
const rulesPath = path.join(__dirname, '..', '..', 'firestore.rules');
const rules = fs.readFileSync(rulesPath, 'utf8');
const token = execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();

async function api(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      'x-goog-user-project': projectId,
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
  console.log('Creating ruleset...');
  const ruleset = await api('POST', `https://firebaserules.googleapis.com/v1/projects/${projectId}/rulesets`, {
    source: { files: [{ name: 'firestore.rules', content: rules }] },
  });
  console.log('Ruleset:', ruleset.name);

  console.log('Publishing release cloud.firestore...');
  const release = await api(
    'PATCH',
    `https://firebaserules.googleapis.com/v1/projects/${projectId}/releases/cloud.firestore?updateMask=rulesetName`,
    {
      name: `projects/${projectId}/releases/cloud.firestore`,
      rulesetName: ruleset.name,
    },
  );
  console.log('Release OK:', release.name || 'cloud.firestore');
})().catch((e) => {
  console.error('Deploy failed:', e.message || e);
  process.exit(1);
});
