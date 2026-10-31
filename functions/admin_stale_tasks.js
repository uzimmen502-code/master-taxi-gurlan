/**
 * ADMIN - «qotib qolgan vazifalar» ro'yxati (D6, ega qarori 2026-10-16).
 *
 * `adminListStaleTasks({ hours })` - har modul bo'yicha holati `hours` soatdan beri
 * o'zgarmagan vazifalar. FAQAT O'QISH: avtomatik qayta tayinlash / vaqt tugashi YO'Q
 * (ega: kuryerga vaqt cheklovi yo'q). Admin ro'yxatni ko'radi va kerak bo'lsa
 * qo'lda harakat qiladi (masalan B1 release: `adminSetCarpetWashStatus`).
 *
 * Modullar (hammasi mavjud hujjatlar, yangi collection YO'Q):
 *   courier_orders    orders: status == 'in_delivery' (type != 'restaurant')
 *   restaurant_orders orders: type == 'restaurant' va restaurantStatus in (ready, picked, arrived), KURYERLI
 *   carpet            carpet_wash_orders: pickup_in_delivery | return_in_delivery | accepted
 *   agro              agro_pickup_orders: pickup_in_delivery | accepted
 *   relay_shipments   shipments: status == 'in_transit'
 *   relay_legs        demands: module == 'logistics' va status in (accepted, in_progress)
 *
 * So'rovlar FAQAT tenglik filtrli (har holat uchun alohida) - composite indeks KERAK EMAS
 * (Firestore bir nechta tenglikni mavjud bir maydonli indekslar bilan birlashtiradi); vaqt
 * bo'yicha filtr KODDA, `QUERY_CAP` bilan chegaralangan skan ustida. Skan chegaraga yetsa -
 * `truncated: true` (eng eskilar qolib ketishi mumkin; indeks qo'shilsa `updatedAt` bo'yicha
 * server filtriga o'tiladi - hozir ega qarori bilan indeks fayli O'ZGARTIRILMAYDI).
 *
 * Javob: faqat id, holat, vaqt, kuryer id, yosh (soat) - mijoz telefoni/ismi/manzili YO'Q (40-qoida).
 * DIQQAT: kuryer id bu loyihada kuryerning telefon raqami (kanonik ID) - shuning uchun faqat
 * admin/superadmin (dispatcher EMAS) chaqira oladi.
 */
'use strict';

const DEFAULT_HOURS = 3;
const MIN_HOURS = 1;
const MAX_HOURS = 168;
/** Bitta so'rovdan ko'pi bilan shuncha hujjat o'qiladi. */
const QUERY_CAP = 200;
/** Bitta modul bo'yicha javobdagi eng ko'p element (eng eskilari birinchi). */
const RESULT_LIMIT = 100;
const HOUR_MS = 3600 * 1000;

const toMs = (v) => {
  if (v && typeof v.toMillis === 'function') return v.toMillis();
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  return null;
};
const firstMs = (...vals) => {
  for (const v of vals) {
    const ms = toMs(v);
    if (ms !== null) return ms;
  }
  return null;
};
const str = (v) => (typeof v === 'string' ? v : '');

/** Modul tavsiflari: so'rovlar (tenglik filtrlari), qoldirish sharti, maydon o'qigichlar. */
const SPECS = Object.freeze([
  {
    key: 'courier_orders',
    collection: 'orders',
    queries: [[['status', 'in_delivery']]],
    keep: (d) => d.type !== 'restaurant',
    status: (d) => str(d.status),
    courier: (d) => str(d.courierId),
    time: (d) => firstMs(d.statusUpdatedAt, d.updatedAt, d.inDeliveryAt, d.createdAt),
  },
  {
    key: 'restaurant_orders',
    collection: 'orders',
    queries: ['ready', 'picked', 'arrived'].map((s) => [['type', 'restaurant'], ['restaurantStatus', s]]),
    keep: (d) => !!d.courierId,
    status: (d) => str(d.restaurantStatus),
    courier: (d) => str(d.courierId),
    time: (d) => firstMs(d.statusUpdatedAt, d.updatedAt, d.createdAt),
  },
  {
    key: 'carpet',
    collection: 'carpet_wash_orders',
    queries: ['pickup_in_delivery', 'return_in_delivery', 'accepted'].map((s) => [['status', s]]),
    keep: () => true,
    status: (d) => str(d.status),
    courier: (d) => (d.status === 'return_in_delivery' ? str(d.returnCourierId) : str(d.pickupCourierId)),
    time: (d) => firstMs(d.updatedAt, d.createdAt),
  },
  {
    key: 'agro',
    collection: 'agro_pickup_orders',
    queries: ['pickup_in_delivery', 'accepted'].map((s) => [['status', s]]),
    keep: () => true,
    status: (d) => str(d.status),
    courier: (d) => str(d.pickupCourierId),
    time: (d) => firstMs(d.updatedAt, d.createdAt),
  },
  {
    key: 'relay_shipments',
    collection: 'shipments',
    queries: [[['status', 'in_transit']]],
    keep: () => true,
    status: (d) => str(d.status),
    courier: (d) => str((d.currentCustodian || {}).id),
    time: (d) => firstMs(d.updatedAt, d.createdAt),
  },
  {
    key: 'relay_legs',
    collection: 'demands',
    queries: ['accepted', 'in_progress'].map((s) => [['module', 'logistics'], ['status', s]]),
    keep: () => true,
    status: (d) => str(d.status),
    courier: (d) => str((d.assignment || {}).providerId),
    time: (d) => firstMs(d.updatedAt, d.createdAt),
  },
]);

/** `hours`: yo'q -> standart; son/son-satr -> butun, 1..168 ga qisqartiriladi; boshqa -> null (xato). */
function parseHours(raw) {
  if (raw === undefined || raw === null) return DEFAULT_HOURS;
  let n;
  if (typeof raw === 'number') n = raw;
  else if (typeof raw === 'string' && raw.trim() !== '') n = Number(raw);
  else return null;
  if (!Number.isFinite(n)) return null;
  return Math.min(MAX_HOURS, Math.max(MIN_HOURS, Math.round(n)));
}

/** Bitta modul: so'rovlar -> kod ichida yosh bo'yicha filtr -> eng eskilari birinchi, chegaralangan. */
async function collectModule(db, spec, nowMs, cutoffMs) {
  const snaps = await Promise.all(spec.queries.map((filters) => {
    let q = db.collection(spec.collection);
    for (const [field, value] of filters) q = q.where(field, '==', value);
    return q.limit(QUERY_CAP).get();
  }));
  let scanned = 0;
  let capped = false;
  const items = [];
  for (const snap of snaps) {
    scanned += snap.size;
    if (snap.size >= QUERY_CAP) capped = true;
    snap.forEach((doc) => {
      const d = doc.data() || {};
      if (!spec.keep(d)) return;
      const ms = spec.time(d);
      // Vaqti yo'q hujjat - yoshini bilib bo'lmaydi: ro'yxatga tushadi (admin ko'rsin).
      if (ms !== null && ms > cutoffMs) return;
      items.push({
        id: doc.id,
        status: spec.status(d),
        updatedAtMs: ms,
        courierId: spec.courier(d),
        ageHours: ms === null ? null : Math.floor(Math.max(0, nowMs - ms) / (HOUR_MS / 10)) / 10,
        // Mijoz tasdig'i kutilmoqda (D2/D7): kuryer qadamini bajargan, mijoz hali "Oldim/Berdim" demagan.
        // Maydon FAQAT belgi bor hujjatda qo'shiladi (eski javob shakli o'zgarmaydi). Belgi yozilganda
        // `updatedAt` o'zgarmaydi - yosh holat o'zgarishidan boshlab sanaladi.
        ...(d.awaitingCustomerConfirm && typeof d.awaitingCustomerConfirm.step === 'string'
          ? { awaitingCustomerStep: d.awaitingCustomerConfirm.step } : {}),
      });
    });
  }
  // Yoshi noma'lumlar (null) eng boshida: ularni admin birinchi ko'radi.
  items.sort((a, b) => (b.ageHours === null ? Infinity : b.ageHours) - (a.ageHours === null ? Infinity : a.ageHours));
  return {
    items: items.slice(0, RESULT_LIMIT),
    total: items.length,
    scanned,
    truncated: capped || items.length > RESULT_LIMIT,
  };
}

function attachAdminStaleTasks(exportsObj, deps) {
  const { functions, db, requireCallerRoles } = deps;
  const { HttpsError } = functions.https;

  exportsObj.adminListStaleTasks = functions.https.onCall(async (data, context) => {
    const t0 = Date.now();
    const actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const hours = parseHours(data && data.hours);
    if (hours === null) throw new HttpsError('invalid-argument', 'HOURS_INVALID', { code: 'HOURS_INVALID', min: MIN_HOURS, max: MAX_HOURS });
    const nowMs = Date.now();
    const cutoffMs = nowMs - hours * HOUR_MS;
    const entries = await Promise.all(SPECS.map(async (spec) => [spec.key, await collectModule(db, spec, nowMs, cutoffMs)]));
    const modules = Object.fromEntries(entries);
    console.log(JSON.stringify({
      action: 'adminListStaleTasks', result: 'ok', userId: actor, hours,
      counts: Object.fromEntries(entries.map(([k, m]) => [k, m.total])),
      truncated: entries.filter(([, m]) => m.truncated).map(([k]) => k),
      durationMs: Date.now() - t0,
    }));
    return { ok: true, hours, generatedAtMs: nowMs, modules };
  });
}

module.exports = {
  DEFAULT_HOURS,
  MIN_HOURS,
  MAX_HOURS,
  QUERY_CAP,
  RESULT_LIMIT,
  SPECS,
  parseHours,
  collectModule,
  attachAdminStaleTasks,
};
