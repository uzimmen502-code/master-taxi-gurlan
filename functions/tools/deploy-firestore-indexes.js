#!/usr/bin/env node
/**
 * Firestore composite indexes deploy (firestore.indexes.json).
 * Auth: functions/service-account.json yoki gcloud token.
 *
 * Usage: node functions/tools/deploy-firestore-indexes.js
 * SSL: node --use-system-ca functions/tools/deploy-firestore-indexes.js
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const projectId = 'master-taxi-gurlan';
const databaseId = '(default)';
const indexesPath = path.join(__dirname, '..', '..', 'firestore.indexes.json');
const keyPath = path.join(__dirname, '..', 'service-account.json');

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

function indexKey(collectionGroup, fields) {
  const parts = fields.map((f) => {
    if (f.order) return `${f.fieldPath}:${f.order}`;
    if (f.arrayConfig) return `${f.fieldPath}:array`;
    return f.fieldPath;
  });
  return `${collectionGroup}|${parts.join(',')}`;
}

function normalizeFields(fields) {
  return fields.map((f) => {
    if (f.order) return { fieldPath: f.fieldPath, order: f.order };
    if (f.arrayConfig) {
      return { fieldPath: f.fieldPath, arrayConfig: f.arrayConfig };
    }
    return { fieldPath: f.fieldPath };
  });
}

async function listExistingIndexes(token) {
  const out = new Set();
  let pageToken = '';
  do {
    const q = pageToken
      ? `?pageToken=${encodeURIComponent(pageToken)}`
      : '';
    const url =
      `https://firestore.googleapis.com/v1/projects/${projectId}` +
      `/databases/${databaseId}/collectionGroups/-/indexes${q}`;
    const data = await api('GET', url, null, token);
    for (const idx of data.indexes || []) {
      const cg = idx.name.split('/collectionGroups/')[1]?.split('/')[0] || '';
      const fields = (idx.fields || []).filter(
        (f) => f.fieldPath !== '__name__',
      );
      out.add(indexKey(cg, fields));
    }
    pageToken = data.nextPageToken || '';
  } while (pageToken);
  return out;
}

(async () => {
  const token = await getToken();
  const spec = JSON.parse(fs.readFileSync(indexesPath, 'utf8'));
  const desired = spec.indexes || [];
  const existing = await listExistingIndexes(token);

  let created = 0;
  let skipped = 0;

  for (const entry of desired) {
    const collectionGroup = entry.collectionGroup;
    const fields = normalizeFields(entry.fields || []);
    const key = indexKey(collectionGroup, fields);
    if (existing.has(key)) {
      console.log('SKIP (exists):', key);
      skipped++;
      continue;
    }

    const body = {
      queryScope: entry.queryScope || 'COLLECTION',
      fields,
    };
    const url =
      `https://firestore.googleapis.com/v1/projects/${projectId}` +
      `/databases/${databaseId}/collectionGroups/${collectionGroup}/indexes`;

    console.log('CREATE:', key);
    const op = await api('POST', url, body, token);
    console.log('  operation:', op.name || 'ok');
    created++;
  }

  console.log(`Done. created=${created} skipped=${skipped}`);
  if (created > 0) {
    console.log(
      'Note: yangi indexlar BUILDING holatida — Firebase Console dan kuzating.',
    );
  }
})().catch((e) => {
  const msg = e.message || String(e);
  console.error('Deploy failed:', msg);
  if (msg.includes('403') || msg.includes('PERMISSION_DENIED')) {
    console.error('');
    console.error('IAM: quyidagi account ga rol qo\'shing:');
    console.error('  Cloud Datastore Index Admin  (yoki Firebase Admin)');
    console.error('  Email: firebase-adminsdk-fbsvc@master-taxi-gurlan.iam.gserviceaccount.com');
    console.error('  https://console.cloud.google.com/iam-admin/iam?project=master-taxi-gurlan');
    console.error('');
    console.error('Yoki Firebase Console → Firestore → Indexes → qo\'lda yarating.');
  }
  process.exit(1);
});
