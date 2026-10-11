/**
 * Админ бўлим рухсатлари (D-ALL-6/9, 2026-10-11): роль — сукут, устига
 * алоҳида одамга бўлим рухсати. `admin_section_grants/{uid}.sections`.
 *
 * - Ким беради: admin ва superadmin (D-ALL-9).
 * - Кимга: фақат панел ролли одам (`admin_pin.PANEL_ROLES`).
 * - Клиент ёзолмайди (rules); ҳар ўзгариш `admin_audit`га (41-қоида).
 * - Бўлим рухсати фақат сервери шу рухсатни танийдиган бўлимлар учун
 *   ишлайди — ҳозир фақат `all_orders` (rules: `order_index` ўқиш).
 */
'use strict';

const GRANT_COL = 'admin_section_grants';
const SECTIONS = ['all_orders'];
const GRANTOR_ROLES = ['admin', 'superadmin'];

function attachAdminSectionGrants(exports, {
  functions, db, admin, canonicalUid, requireCallerRoles, PANEL_ROLES,
}) {
  const fail = (code, msg) => new functions.https.HttpsError('failed-precondition', msg, { code });

  exports.adminSetSectionGrant = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const actor = await requireCallerRoles(context, GRANTOR_ROLES, 'Рухсат бериш фақат админ учун');
    const section = String((data && data.section) || '').trim();
    const granted = (data && data.granted) === true;
    const target = canonicalUid(String((data && data.targetPhone) || ''));
    if (!SECTIONS.includes(section)) {
      throw new functions.https.HttpsError('invalid-argument', 'Бундай бўлим йўқ', { code: 'SECTION_UNKNOWN' });
    }
    if (!target || target.length < 12) {
      throw new functions.https.HttpsError('invalid-argument', 'Телефон нотўғри', { code: 'TARGET_INVALID' });
    }

    // Эски 9 хонали `users` ҳужжати ҳам бўлиши мумкин.
    let userSnap = await db.collection('users').doc(target).get();
    if (!userSnap.exists && target.startsWith('998')) {
      userSnap = await db.collection('users').doc(target.slice(3)).get();
    }
    const role = String(((userSnap.exists && userSnap.data()) || {}).role || '');
    if (granted && !PANEL_ROLES.includes(role)) {
      throw fail('TARGET_NOT_PANEL', 'Рухсат фақат админ панел ходимига берилади');
    }

    const ref = db.collection(GRANT_COL).doc(target);
    const result = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const current = Array.isArray((snap.data() || {}).sections) ? snap.data().sections : [];
      const has = current.includes(section);
      if (has === granted) return { changed: false, sections: current };
      const next = granted ? [...current, section] : current.filter((s) => s !== section);
      t.set(ref, {
        sections: next,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: actor,
      }, { merge: true });
      t.set(db.collection('admin_audit').doc(), {
        kind: granted ? 'section_grant' : 'section_revoke',
        actor,
        target,
        targetRole: role,
        section,
        at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { changed: true, sections: next };
    });

    console.log(JSON.stringify({
      action: 'adminSetSectionGrant', userId: actor, targetTail: target.slice(-4),
      section, granted, result: result.changed ? 'changed' : 'unchanged',
      durationMs: Date.now() - started,
    }));
    return { ok: true, ...result };
  });
}

module.exports = { attachAdminSectionGrants, GRANT_COL, SECTIONS, GRANTOR_ROLES };
