const fs = require('fs');
const path = require('path');

const p = path.join(__dirname, '..', 'index.js');
let s = fs.readFileSync(p, 'utf8');

const marker = '/** Admin web: shikoyatni hal qilindi deb belgilash. */';
const insert = `const ADMIN_SELL_SUBMISSION_STATUSES = new Set(['pending', 'reviewed', 'archived']);

/** Admin web: sell_submissions status / forward (CF-only writes). */
exports.adminUpdateSellSubmission = functions.https.onCall(async (data, context) => {
  const adminDocId = await assertAdmin(String(data.adminPhone || ''), context);
  const submissionId = String(data.submissionId || '').trim();
  if (!submissionId) {
    throw new functions.https.HttpsError('invalid-argument', 'submissionId required');
  }
  const ref = db.collection('sell_submissions').doc(submissionId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'submission not found');
  }

  const action = String(data.action || 'setStatus').trim();
  if (action === 'setStatus') {
    const status = String(data.status || '').trim();
    if (!ADMIN_SELL_SUBMISSION_STATUSES.has(status)) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid status');
    }
    const patch = {
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      moderatedBy: adminDocId,
    };
    if (data.adminNote != null) {
      patch.adminNote = String(data.adminNote).trim();
    }
    await ref.update(patch);
    return { ok: true, submissionId, status };
  }

  if (action === 'forward') {
    const audience = String(data.forwardAudience || '').trim();
    if (!['all', 'selected'].includes(audience)) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid audience');
    }
    const patch = {
      forwardAudience: audience,
      forwardedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      moderatedBy: adminDocId,
    };
    if (audience === 'selected') {
      const raw = Array.isArray(data.targetUserIds) ? data.targetUserIds : [];
      const normalized = [...new Set(raw.map((x) => canonicalUid(String(x || '')))
        .filter((p) => p.length >= 9))];
      if (normalized.length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'targetUserIds required');
      }
      patch.visibleToUserIds = normalized;
    }
    if (data.adminNote != null && String(data.adminNote).trim()) {
      patch.adminNote = String(data.adminNote).trim();
    }
    await ref.update(patch);
    return { ok: true, submissionId, forwardAudience: audience };
  }

  throw new functions.https.HttpsError('invalid-argument', 'Unknown action');
});

/** Admin web: dating report resolve. */
exports.adminResolveDatingReport = functions.https.onCall(async (data, context) => {
  const adminDocId = await assertAdmin(String(data.adminPhone || ''), context);
  const reportId = String(data.reportId || '').trim();
  if (!reportId) {
    throw new functions.https.HttpsError('invalid-argument', 'reportId required');
  }
  const ref = db.collection('reports').doc(reportId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', 'report not found');
  }
  await ref.update({
    status: 'resolved',
    resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    resolvedBy: adminDocId,
  });
  return { ok: true, reportId };
});

`;

if (s.includes('exports.adminUpdateSellSubmission')) {
  console.log('already patched');
  process.exit(0);
}
if (!s.includes(marker)) {
  console.error('marker not found');
  process.exit(1);
}
s = s.replace(marker, insert + marker);
fs.writeFileSync(p, s);
console.log('patched admin sell + dating CFs');
