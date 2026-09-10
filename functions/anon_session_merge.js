'use strict';

/**
 * Anonymous Session + Account Merge — 1-bosqich (data model & merge engine).
 *
 * anon_sessions/{sessionId}            sessionId = Firebase Anonymous Auth uid
 * anon_sessions/{sessionId}/engagement/{eventId}
 * user_engagement_index/{userId}       userId = canonicalPhoneId (yoki hali
 *                                       merge bo'lmagan anon sessionId)
 *
 * Klient wiring (signInAnonymously, feed/like/save ulash) keyingi bosqichda —
 * bu modul faqat merge/backfill backend qismini beradi.
 */

const ENGAGEMENT_PAGE = 400;
const BATCH_CHUNK = 400;
const VIEWED_CLIP_CAP = 500;

function attachAnonSessionMerge(exports, deps) {
  const { functions, db, admin, canonicalUid, requireCallerRoles } = deps;

  function callerUid(context) {
    const tokenPhone = String(
        (context.auth && context.auth.token && context.auth.token.phone_number) || '')
        .replace(/\D/g, '');
    return canonicalUid(tokenPhone);
  }

  function chunk(arr, size) {
    const out = [];
    for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
    return out;
  }

  async function readAllEngagement(sessionId) {
    const out = [];
    let cursor = null;
    for (;;) {
      let q = db.collection('anon_sessions').doc(sessionId)
          .collection('engagement')
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(ENGAGEMENT_PAGE);
      if (cursor) q = q.startAfter(cursor);
      const snap = await q.get();
      if (snap.empty) break;
      for (const doc of snap.docs) out.push(doc.data() || {});
      cursor = snap.docs[snap.docs.length - 1];
      if (snap.size < ENGAGEMENT_PAGE) break;
    }
    return out;
  }

  function capArray(arr, cap) {
    if (!Array.isArray(arr) || arr.length <= cap) return arr;
    return arr.slice(arr.length - cap);
  }

  /**
   * Callable: {sessionId, anonIdToken} — chaqiruvchi Auth qilingan bo'lishi
   * kerak (custom token, checkPhoneDeviceLock muvaffaqiyatli bo'lgach).
   * `anonIdToken` — sessionId'ga tegishli Firebase Anonymous Auth ID token
   * (egalik isboti): faqat shu sessionId bilan haqiqatan anonim kirgan
   * klient merge so'rashi mumkin, sessionId'ni bilishning o'zi kifoya emas.
   * Idempotent: `anon_sessions/{sessionId}.status` merge holatini belgilaydi,
   * har bir engagement yozuvi deterministik hujjat ID bilan (clipId) yoziladi
   * — qayta chaqirilsa ustidan yozadi, ikki marta qo'shilmaydi.
   */
  exports.mergeAnonymousSession = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Auth required');
    }
    const userId = callerUid(context);
    if (!userId || userId.length < 12) {
      throw new functions.https.HttpsError('unauthenticated', 'Phone token required');
    }
    const sessionId = String((data && data.sessionId) || '').trim();
    if (!sessionId) {
      throw new functions.https.HttpsError('invalid-argument', 'sessionId required');
    }
    const anonIdToken = String((data && data.anonIdToken) || '').trim();
    if (!anonIdToken) {
      throw new functions.https.HttpsError('invalid-argument', 'anonIdToken required');
    }

    let decodedAnon;
    try {
      decodedAnon = await admin.auth().verifyIdToken(anonIdToken);
    } catch (e) {
      throw new functions.https.HttpsError('unauthenticated', 'Invalid or expired anonIdToken');
    }
    if (decodedAnon.uid !== sessionId) {
      throw new functions.https.HttpsError(
          'permission-denied', 'anonIdToken does not match sessionId');
    }
    if (!decodedAnon.firebase || decodedAnon.firebase.sign_in_provider !== 'anonymous') {
      throw new functions.https.HttpsError(
          'permission-denied', 'anonIdToken is not from an anonymous sign-in');
    }

    const sessionRef = db.collection('anon_sessions').doc(sessionId);
    const sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'anon_sessions/{sessionId} not found');
    }
    const session = sessionSnap.data() || {};

    if (session.status === 'merged') {
      if (session.mergedToUserId === userId) {
        return {ok: true, alreadyMerged: true, userId};
      }
      throw new functions.https.HttpsError(
          'failed-precondition', 'Session already merged to a different user');
    }
    if (session.status && session.status !== 'active') {
      throw new functions.https.HttpsError(
          'failed-precondition', `Session status is '${session.status}', not mergeable`);
    }

    const events = await readAllEngagement(sessionId);

    const likedClipIds = new Set();
    const savedClipIds = new Set();
    const viewedClipIds = new Set();
    const writes = [];

    for (const ev of events) {
      const clipId = String(ev.clipId || '').trim();
      if (!clipId) continue;
      const type = String(ev.type || '').trim();
      const clipRef = db.collection('tv_clips').doc(clipId);
      if (type === 'like') {
        likedClipIds.add(clipId);
        writes.push({ref: clipRef.collection('likes').doc(userId), data: {
          likedAt: admin.firestore.FieldValue.serverTimestamp(),
          fromAnonMerge: true,
        }});
      } else if (type === 'save') {
        savedClipIds.add(clipId);
        writes.push({ref: db.collection('users').doc(userId)
            .collection('saved_tv_clips').doc(clipId), data: {
          savedAt: admin.firestore.FieldValue.serverTimestamp(),
          fromAnonMerge: true,
        }});
      } else if (type === 'view') {
        viewedClipIds.add(clipId);
        writes.push({ref: clipRef.collection('views').doc(userId), data: {
          viewedAt: admin.firestore.FieldValue.serverTimestamp(),
          fromAnonMerge: true,
        }});
      }
      // 'skip' — hozircha faqat user_engagement_index'ga emas, kelajakdagi
      // ranking signal log'iga tegishli; bu bosqichda alohida yozilmaydi.
    }

    for (const part of chunk(writes, BATCH_CHUNK)) {
      const batch = db.batch();
      for (const w of part) batch.set(w.ref, w.data, {merge: true});
      await batch.commit();
    }

    const indexRef = db.collection('user_engagement_index').doc(userId);
    const indexSnap = await indexRef.get();
    const existing = indexSnap.exists ? (indexSnap.data() || {}) : {};
    const mergedViewed = capArray(
        Array.from(new Set([...(existing.viewedClipIds || []), ...viewedClipIds])),
        VIEWED_CLIP_CAP);

    const indexUpdate = {
      viewedClipIds: mergedViewed,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (likedClipIds.size) {
      indexUpdate.likedClipIds = admin.firestore.FieldValue.arrayUnion(...likedClipIds);
    }
    if (savedClipIds.size) {
      indexUpdate.savedClipIds = admin.firestore.FieldValue.arrayUnion(...savedClipIds);
    }
    await indexRef.set(indexUpdate, {merge: true});

    await sessionRef.set({
      status: 'merged',
      mergedToUserId: userId,
      mergedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      ok: true,
      userId,
      likedCount: likedClipIds.size,
      savedCount: savedClipIds.size,
      viewedCount: viewedClipIds.size,
    };
  });

  /**
   * Admin-only, bir martalik: mavjud registered foydalanuvchilarning
   * tarixiy tv_clips likes/views va users collection'idagi saved_tv_clips yozuvlarini
   * user_engagement_index'ga retroaktiv to'ldiradi.
   * `migrateOldBindings`/`migrateFloatToWallet` konvensiyasiga mos: dryRun
   * qo'llab-quvvatlaydi, hisob qaytaradi, productionda ehtiyotkorlik bilan
   * ishga tushiriladi.
   */
  exports.backfillEngagementIndex = functions
      .runWith({timeoutSeconds: 540, memory: '512MB'})
      .https.onCall(async (data, context) => {
        await requireCallerRoles(context, ['superadmin'], 'Superadmin role required');
        const dryRun = !!(data && data.dryRun);

        const perUser = new Map();
        const bump = (userId, field, clipId) => {
          if (!userId || !clipId) return;
          if (!perUser.has(userId)) {
            perUser.set(userId, {likedClipIds: new Set(), savedClipIds: new Set(), viewedClipIds: new Set()});
          }
          perUser.get(userId)[field].add(clipId);
        };

        const likesSnap = await db.collectionGroup('likes').get();
        for (const doc of likesSnap.docs) {
          const clipId = doc.ref.parent.parent ? doc.ref.parent.parent.id : '';
          bump(doc.id, 'likedClipIds', clipId);
        }

        const viewsSnap = await db.collectionGroup('views').get();
        for (const doc of viewsSnap.docs) {
          const clipId = doc.ref.parent.parent ? doc.ref.parent.parent.id : '';
          bump(doc.id, 'viewedClipIds', clipId);
        }

        const savedSnap = await db.collectionGroup('saved_tv_clips').get();
        for (const doc of savedSnap.docs) {
          const userId = doc.ref.parent.parent ? doc.ref.parent.parent.id : '';
          bump(userId, 'savedClipIds', doc.id);
        }

        let written = 0;
        if (!dryRun) {
          for (const [userId, sets] of perUser.entries()) {
            const indexRef = db.collection('user_engagement_index').doc(userId);
            const update = {
              viewedClipIds: capArray([...sets.viewedClipIds], VIEWED_CLIP_CAP),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            if (sets.likedClipIds.size) {
              update.likedClipIds = admin.firestore.FieldValue.arrayUnion(...sets.likedClipIds);
            }
            if (sets.savedClipIds.size) {
              update.savedClipIds = admin.firestore.FieldValue.arrayUnion(...sets.savedClipIds);
            }
            await indexRef.set(update, {merge: true});
            written += 1;
          }
        }

        return {
          ok: true,
          dryRun,
          usersFound: perUser.size,
          usersWritten: dryRun ? 0 : written,
        };
      });
}

module.exports = {attachAnonSessionMerge};
