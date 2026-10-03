'use strict';

/**
 * 13.2.5 — FCM YUBORISH QATLAMI.
 *
 * Т-6 bo'yicha mavjud push quvuridan uchta farq:
 *
 * 1) KO'P QURILMA. Repoda `users.fcmToken` — BITTA satr. Ikkinchi
 *    qurilmaga kirgan foydalanuvchi push olmaydi. Yadro
 *    `users/{id}/fcm_tokens/{token}` subkolleksiyasini ishlatadi.
 *    Eski `fcmToken` maydoni ham O'QILADI (180+ mavjud funksiya uni
 *    yozadi) — migratsiya majburiy emas, strangler pattern.
 *
 * 2) COLLAPSE. `collapseKey = demandId`: talab olinganda yoki bekor
 *    qilinganda eski xabar YANGILANADI («Buyurtma olindi»), telefonda
 *    ishlamaydigan «Qabul qilish» tugmasi qolib ketmaydi.
 *
 * 3) PLATFORMA HAQIQATI. Faqat `data` xabar iOS'da ilova o'ldirilganda
 *    KO'RINMAYDI. Shuning uchun `notification` + `data` birga yuboriladi.
 *    Android'da `flutter_local_notifications` action tugmalarini o'zi
 *    chizadi (P2); iOS'da `apns.payload.aps.category` ishlatiladi.
 *
 * `notifications` kolleksiyasiga hujjat YOZILMAYDI: yadroning inbox'i —
 * `demand_matches`. Ikkita inbox bo'lsa, o'qilmagan sonlar ajralib
 * ketadi va foydalanuvchi qaysi biriga ishonishini bilmaydi.
 */

const { candidateIdsFor, pushLogKey } = require('../core/ids');

const TOKENS_SUB = 'fcm_tokens';
const PUSH_LOG = 'demand_push_log';

/**
 * Foydalanuvchining barcha FCM tokenlari.
 *
 * Tartib: yangi subkolleksiya birinchi, eski yakka maydon — zaxira.
 * 9/12 xonali ikki ID shakli ham qaraladi (eski hujjatlar).
 */
async function tokensFor(db, uid) {
  const ids = candidateIdsFor(uid);
  const out = new Set();

  for (const id of ids) {
    try {
      const snap = await db.collection('users').doc(id).collection(TOKENS_SUB).get();
      for (const d of snap.docs) {
        const t = (d.data() || {}).token || d.id;
        if (t) out.add(String(t));
      }
    } catch (e) {
      console.error(`fcm_tokens o'qilmadi (${id}): ${e.message}`);
    }
  }

  // Zaxira: eski yakka maydon.
  if (out.size === 0) {
    for (const id of ids) {
      const snap = await db.collection('users').doc(id).get();
      const t = snap.exists ? (snap.data() || {}).fcmToken : '';
      if (t) { out.add(String(t)); break; }
    }
  }

  return Array.from(out);
}

/**
 * Ishlamaydigan tokenni o'chirish.
 *
 * Busiz `users/{id}/fcm_tokens` o'lik tokenlar bilan to'lib ketadi va
 * har push uchun bekorga urinish qilinadi (FCM kvotasi va vaqt).
 */
async function pruneToken(db, uid, token) {
  for (const id of candidateIdsFor(uid)) {
    try {
      await db.collection('users').doc(id).collection(TOKENS_SUB).doc(token).delete();
    } catch (_) { /* yo'q bo'lsa — yaxshi */ }
  }
}

/**
 * Xabar yuklamasini quradi.
 *
 * @param {object} p
 * @param {string} p.demandId   collapse kaliti
 * @param {string} p.mode       dispatch | quote | alert
 * @param {{title: string, body: string}} p.text
 * @param {string} [p.imageUrl]
 */
function buildMessage(p) {
  const highPriority = p.mode === 'dispatch';

  const data = {
    type: 'demand_match',
    demandId: String(p.demandId),
    module: String(p.module || ''),
    mode: String(p.mode || ''),
    // Deep link — Т-6.4: ANIQ MANZIL VA TELEFON YO'Q, faqat id.
    screen: `ava://demand/${p.demandId}`,
    action: highPriority ? 'accept' : 'offer',
  };

  const msg = {
    notification: { title: p.text.title, body: p.text.body },
    data,
    android: {
      priority: highPriority ? 'high' : 'normal',
      collapseKey: String(p.demandId),
      notification: {
        channelId: highPriority ? 'ava_dispatch' : 'ava_demands',
        tag: String(p.demandId),
        ...(p.imageUrl ? { imageUrl: p.imageUrl } : {}),
      },
    },
    apns: {
      headers: {
        'apns-collapse-id': String(p.demandId),
        'apns-priority': highPriority ? '10' : '5',
      },
      payload: {
        aps: {
          sound: highPriority ? 'ava_dispatch.caf' : 'default',
          category: highPriority ? 'DEMAND_DISPATCH' : 'DEMAND_QUOTE',
          'mutable-content': p.imageUrl ? 1 : 0,
        },
      },
      ...(p.imageUrl ? { fcmOptions: { imageUrl: p.imageUrl } } : {}),
    },
  };

  return msg;
}

/**
 * «Buyurtma olindi» — collapse orqali ESKI xabarni almashtiradi.
 *
 * Konsepsiya talabi: «Qolganlarning push'i yangilanib, "Buyurtma olindi"
 * deb o'zgaradi. Eski "Qabul qilish" tugmasi telefonda qolmaydi.»
 */
function buildTakenMessage(demandId, module) {
  return {
    notification: { title: 'Buyurtma olindi', body: 'Bu so\'rov boshqa ijrochiga berildi' },
    data: { type: 'demand_taken', demandId: String(demandId), module: String(module || '') },
    android: {
      priority: 'normal',
      collapseKey: String(demandId),
      notification: { channelId: 'ava_demands', tag: String(demandId) },
    },
    apns: {
      headers: { 'apns-collapse-id': String(demandId), 'apns-priority': '5' },
      payload: { aps: { sound: 'default' } },
    },
  };
}

/**
 * Yuborish + idempotentlik jurnali.
 *
 * `demand_push_log/{demandId}_{providerId}` — «bir taklifchiga bir talab
 * bo'yicha bitta push, hech qachon takrorlanmaydi» qoidasining amaliy
 * shakli. Jurnal YOZILGANDAN KEYIN yuborilmaydi, balki OLDIN: ikkita
 * parallel chaqiruv bo'lsa, ikkinchisi jurnalni ko'rib to'xtaydi.
 */
async function sendToProvider(deps, params) {
  const { db, messaging } = deps;
  const {
    demandId, providerId, message, reason, dryRun = false,
  } = params;

  const logRef = db.collection(PUSH_LOG).doc(pushLogKey(demandId, providerId));

  const existing = await logRef.get();
  if (existing.exists && (existing.data() || {}).sent === true) {
    return { sent: false, reason: 'already_sent', tokens: 0 };
  }

  const tokens = await tokensFor(db, providerId);
  if (tokens.length === 0) {
    await logRef.set({
      demandId, providerId, sent: false, reason: 'no_token', at: new Date(),
    }, { merge: true });
    return { sent: false, reason: 'no_token', tokens: 0 };
  }

  if (dryRun) {
    await logRef.set({
      demandId, providerId, sent: false, reason: 'shadow_mode',
      tokenCount: tokens.length, at: new Date(),
    }, { merge: true });
    return { sent: false, reason: 'shadow_mode', tokens: tokens.length };
  }

  // Jurnal OLDIN — parallel chaqiruvda ikkinchi push ketmasligi uchun.
  await logRef.set({
    demandId, providerId, sent: true, reason: reason || 'send',
    tokenCount: tokens.length, at: new Date(),
  }, { merge: true });

  let ok = 0;
  const dead = [];
  try {
    const res = await messaging.sendEach(
      tokens.map((token) => ({ ...message, token })),
    );
    res.responses.forEach((r, i) => {
      if (r.success) { ok += 1; return; }
      const code = r.error && r.error.code;
      if (code === 'messaging/registration-token-not-registered'
        || code === 'messaging/invalid-registration-token') {
        dead.push(tokens[i]);
      }
    });
  } catch (e) {
    console.error(`FCM yuborish xatosi (${providerId}): ${e.message}`);
    await logRef.set({ sent: false, reason: `fcm_error: ${e.message}` }, { merge: true });
    return { sent: false, reason: 'fcm_error', tokens: tokens.length };
  }

  for (const t of dead) await pruneToken(db, providerId, t);

  return { sent: ok > 0, reason: reason || 'send', tokens: tokens.length, delivered: ok };
}

module.exports = {
  TOKENS_SUB,
  PUSH_LOG,
  tokensFor,
  pruneToken,
  buildMessage,
  buildTakenMessage,
  sendToProvider,
};
