/**
 * ҲИСОБНИ АВТОМАТИК ЎЧИРИШ — ядро: шахсни аниқлаш ва БЛОКЛОВЧИ ҳолатлар
 * (docs/hisobni_ochirish_2026-10-24_uz.md, эга қарорлари 2026-10-24).
 *
 * Бу файлда ФАҚАТ ўқиш: ҳеч нарса ёзилмайди/ўчирилмайди. Ёзувчи қадамлар алоҳида модулда.
 *
 * Қоида (эга): фаол буюртма / сафар / курьер қарзи, кутилаётган payout·ечиш·тўлдириш ва ходим роли
 * бўлса ўчириш БЛОКЛАНАДИ. Текшириш сўровда ВА ижро пайтида такрорланади (ҳолат орада ўзгариши мумкин).
 *
 * Хавфсизлик йўналиши: текширув аниқ эмас (кесилди, ўқиб бўлмади) бўлса — БЛОК (`SCAN_TRUNCATED`),
 * «блок йўқ» эмас. Нотўғри «рухсат» = йўқолган пул/буюртма (53-банд).
 *
 * Майдонлар (CONFIRMED rules/kod'дан): orders.userPhone/courierId/restaurantId, carpet_wash_orders и
 * agro_pickup_orders.customerPhone, trips.userPhone/driverId, intercity_bookings.userPhone/driverId,
 * restaurant_bookings.userPhone, oil_change_bookings.uid, shipments.ownerId/assignedProviderIds,
 * demands.ownerId, china_inquiries.ownerId, wallet_topup_requests/wallet_withdraw_requests.uid,
 * payout_requests.userPhone, delivery_routes.courierId, provider_capabilities.debt.taxi (accountId орқали),
 * ledger_accounts/{courier_cash:phone12 | driver_float:uid}.balance.
 * «Фаол» қийматлар рўйхати — PROPOSED (инвентаризация, 2026-10-24); битта манба шу файл, тест қулфлайди.
 * UNKNOWN (A1 таҳлили): collection_tasks, supplier_payable, гилам `delivered` маъноси — ҳозирча текширилмайди.
 */
'use strict';

/** users.role: ходим/админ/молия — ўз-ўзини ўчира олмайди (аввал рол олинади). rules: isStaff ∪ isFinanceReader. */
const STAFF_ROLES = Object.freeze(['admin', 'superadmin', 'dispatcher', 'staff', 'finance', 'auditor']);

const ACTIVE = Object.freeze({
  ordersStatus: Object.freeze(['new', 'accepted', 'ready', 'in_delivery', 'courier']),
  ordersFulfillment: Object.freeze(['pending', 'confirmed', 'ready', 'courier_picked', 'arrived']),
  restaurantStatus: Object.freeze(['placed', 'accepted', 'ready', 'picked', 'arrived']),
  carpet: Object.freeze([
    'new', 'accepted', 'pickup_ready', 'pickup_in_delivery', 'picked_up', 'washing', 'drying', 'ready',
    'return_ready', 'return_in_delivery',
  ]),
  agro: Object.freeze(['new', 'accepted', 'pickup_in_delivery', 'picked_up']),
  trips: Object.freeze(['searching', 'accepted', 'pending']),
  intercity: Object.freeze(['pending', 'confirmed']),
  tableBooking: Object.freeze(['requested', 'confirmed']),
  oilBooking: Object.freeze(['new']),
  shipmentStatus: Object.freeze(['awaiting_payment', 'ready', 'in_transit', 'disputed', 'lost']),
  shipmentPayment: Object.freeze(['pending', 'escrow_funded', 'release_approved', 'escrow_frozen', 'refund_pending']),
  demands: Object.freeze(['active', 'accepted', 'in_progress', 'disputed']),
  china: Object.freeze(['new', 'sent', 'quoted']),
  settlements: Object.freeze(['pending']),
  routes: Object.freeze(['ready', 'active']),
  payout: Object.freeze(['pending']),
  withdraw: Object.freeze(['pending', 'approved']),
  topup: Object.freeze(['awaiting_transfer', 'awaiting_review']),
});

/** Бир қидирувда ўқиладиган ҳужжатлар чегараси; ошса — ишончли хулоса йўқ → блок. */
const SCAN_CAP = 1000;
const IN_CHUNK = 10;

const digitsOf = (v) => String(v == null ? '' : v).replace(/\D/g, '');

/**
 * Телефоннинг барча сақланиш шакллари: 12 хонали (998…), эски 9 хонали, `+998…`.
 * Бошқа шакл (масалан, «90 123-45-67» хом матн) бу ерда аниқланмайди — UNKNOWN, ҳужжатда ёзилган.
 */
function phoneForms(value) {
  const d = digitsOf(value);
  let d12 = '';
  let d9 = '';
  if (d.length === 12 && d.startsWith('998')) {
    d12 = d;
    d9 = d.slice(3);
  } else if (d.length === 9) {
    d9 = d;
    d12 = `998${d}`;
  } else {
    return { d12: '', d9: '', plus12: '', all: [] };
  }
  const plus12 = `+${d12}`;
  return { d12, d9, plus12, all: [d12, d9, plus12] };
}

const uniq = (arr) => [...new Set(arr.filter((x) => typeof x === 'string' && x !== ''))];

/**
 * Шахсни аниқлаш тўплами. Манба: `users` ҳужжати (иккала ID шакли), `users.phone`,
 * `users.accountId`, `users.realtyOwnerKey`, `device_bindings.phone` (бармоқ изи ҳешлари).
 * Телефон алмашгандан кейин эски калит остидаги маълумот қолади (changeDevicePhone) — шунинг учун
 * `users.phone` ва `device_bindings.phone` ҳам қўшилади.
 */
async function resolveIdentity(db, uid) {
  const base = phoneForms(uid);
  if (!base.d12) throw new Error('ACCOUNT_UID_INVALID');
  const userDocIds = [];
  const roles = [];
  const accountIds = [];
  const phones = [...base.all];
  const realtyOwnerKeys = [];
  for (const id of [base.d12, base.d9]) {
    const snap = await db.collection('users').doc(id).get();
    if (!snap.exists) continue;
    userDocIds.push(id);
    const u = snap.data() || {};
    if (u.role) roles.push(String(u.role).trim().toLowerCase());
    if (u.accountId) accountIds.push(String(u.accountId));
    if (u.realtyOwnerKey) realtyOwnerKeys.push(String(u.realtyOwnerKey));
    const own = phoneForms(u.phone);
    phones.push(...own.all);
  }
  const phoneSet = uniq(phones);
  const deviceHashes = [];
  for (const p of uniq(phoneSet.filter((x) => /^\d{12}$/.test(x)))) {
    const q = await db.collection('device_bindings').where('phone', '==', p).limit(50).get();
    q.forEach((d) => deviceHashes.push(d.id));
  }
  const allForms = uniq(phoneSet.flatMap((p) => phoneForms(p).all));
  return {
    uid: base.d12,
    d12: base.d12,
    d9: base.d9,
    ids: uniq([base.d12, base.d9, ...allForms.filter((x) => /^\d+$/.test(x))]),
    forms: allForms,
    userDocIds: uniq(userDocIds),
    accountIds: uniq(accountIds),
    realtyOwnerKeys: uniq(realtyOwnerKeys),
    deviceHashes: uniq(deviceHashes),
    roles: uniq(roles),
  };
}

const chunk = (arr, n) => {
  const out = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
};

/**
 * `col`да `field` қийматлари `values` га тенг ҳужжатларни ўқийди (майдонлар `select` билан),
 * `isActive(data)` тўғри бўлганларини қайтаради. `array-contains-any` учун `op`.
 * @returns {{ active: Array<{id:string}>, truncated: boolean }}
 */
async function scan(db, col, field, values, select, isActive, { op = 'in', cap = SCAN_CAP } = {}) {
  const vals = uniq(values.map((v) => (v == null ? '' : String(v))));
  const active = [];
  let truncated = false;
  for (const part of chunk(vals, IN_CHUNK)) {
    const q = db.collection(col).where(field, op === 'array' ? 'array-contains-any' : 'in', part)
      .select(...select).limit(cap + 1);
    const snap = await q.get();
    if (snap.size > cap) truncated = true;
    let n = 0;
    snap.forEach((d) => {
      n += 1;
      if (n > cap) return;
      if (isActive(d.data() || {})) active.push({ id: d.id });
    });
  }
  return { active, truncated };
}

const inList = (list, v) => list.includes(String(v == null ? '' : v));

/**
 * Блокловчи ҳолатлар рўйхати. Бўш массив = ўчиришга тўсиқ йўқ.
 * Ҳар элемент: { code, area, count, sample[] }. `area`: orders | trips | courier | money | staff | other —
 * клиент шу гуруҳ бўйича оддий тилда тушунтиради (45-банд: техник атама кўрсатилмайди).
 */
async function findBlockers(db, identity, { cap = SCAN_CAP } = {}) {
  const out = [];
  const add = (code, area, hit) => {
    if (hit.truncated) {
      out.push({ code: 'SCAN_TRUNCATED', area: 'other', count: 0, sample: [], detail: code });
      return;
    }
    if (hit.active.length > 0) {
      out.push({ code, area, count: hit.active.length, sample: hit.active.slice(0, 3).map((x) => x.id) });
    }
  };
  const sc = (col, field, values, select, fn, opts) => scan(db, col, field, values, select, fn, { cap, ...opts });
  const A = ACTIVE;
  const forms = identity.forms.length > 0 ? identity.forms : phoneForms(identity.uid).all;
  const ids = identity.ids.length > 0 ? identity.ids : phoneForms(identity.uid).all;

  // ── Ходим роли
  if (identity.roles.some((r) => STAFF_ROLES.includes(r))) {
    out.push({ code: 'STAFF_ROLE', area: 'staff', count: 1, sample: [] });
  }

  // ── Буюртмалар
  const orderActive = (d) => inList(A.ordersStatus, d.status)
    || inList(A.ordersFulfillment, d.fulfillmentStatus)
    || inList(A.restaurantStatus, d.restaurantStatus);
  const orderSel = ['status', 'fulfillmentStatus', 'restaurantStatus'];
  add('ORDER_ACTIVE', 'orders', await sc('orders', 'userPhone', forms, orderSel, orderActive));
  add('COURIER_ORDER_ACTIVE', 'courier', await sc('orders', 'courierId', ids, orderSel, orderActive));
  add('CARPET_ACTIVE', 'orders',
    await sc('carpet_wash_orders', 'customerPhone', forms, ['status'], (d) => inList(A.carpet, d.status)));
  add('AGRO_ACTIVE', 'orders',
    await sc('agro_pickup_orders', 'customerPhone', forms, ['status'], (d) => inList(A.agro, d.status)));

  // Ресторан эгаси: ўз ресторанларига кирган фаол буюртмалар
  const restSnap = await sc('restaurants', 'ownerUid', ids, ['ownerUid'], () => true);
  if (restSnap.truncated) {
    out.push({ code: 'SCAN_TRUNCATED', area: 'other', count: 0, sample: [], detail: 'RESTAURANT_OWNED' });
  } else if (restSnap.active.length > 0) {
    add('RESTAURANT_ORDER_ACTIVE', 'orders',
      await sc('orders', 'restaurantId', restSnap.active.map((r) => r.id), ['restaurantStatus'],
        (d) => inList(A.restaurantStatus, d.restaurantStatus)));
  }

  // ── Сафарлар ва бронлар
  const tripActive = (d) => inList(A.trips, d.status);
  add('TRIP_ACTIVE', 'trips', await sc('trips', 'userPhone', forms, ['status'], tripActive));
  add('TRIP_DRIVER_ACTIVE', 'trips', await sc('trips', 'driverId', ids, ['status'], tripActive));
  add('TRIP_DRIVER_ACTIVE', 'trips', await sc('trips', 'acceptedDriverId', ids, ['status'], tripActive));
  const icActive = (d) => inList(A.intercity, d.status);
  add('INTERCITY_ACTIVE', 'trips', await sc('intercity_bookings', 'userPhone', forms, ['status'], icActive));
  add('INTERCITY_ACTIVE', 'trips', await sc('intercity_bookings', 'driverId', ids, ['status'], icActive));
  add('TABLE_BOOKING_ACTIVE', 'trips',
    await sc('restaurant_bookings', 'userPhone', forms, ['status'], (d) => inList(A.tableBooking, d.status)));
  add('OIL_BOOKING_ACTIVE', 'trips',
    await sc('oil_change_bookings', 'uid', ids, ['status'], (d) => inList(A.oilBooking, d.status)));

  // ── Юк (relay), талаб, Хитой сўровлари
  const shipActive = (d) => inList(A.shipmentStatus, d.status) || inList(A.shipmentPayment, d.paymentStatus);
  const shipSel = ['status', 'paymentStatus'];
  add('SHIPMENT_ACTIVE', 'other', await sc('shipments', 'ownerId', ids, shipSel, shipActive));
  add('SHIPMENT_ACTIVE', 'other',
    await sc('shipments', 'assignedProviderIds', ids, shipSel, shipActive, { op: 'array' }));
  add('DEMAND_ACTIVE', 'other',
    await sc('demands', 'ownerId', ids, ['status'], (d) => inList(A.demands, d.status)));
  add('CHINA_ACTIVE', 'other',
    await sc('china_inquiries', 'ownerId', ids, ['status'], (d) => inList(A.china, d.status)));

  // ── Ҳисоб-китоб ва курьер
  const stlActive = (d) => inList(A.settlements, d.state);
  add('SETTLEMENT_PENDING', 'money', await sc('settlements', 'driverUid', ids, ['state'], stlActive));
  add('SETTLEMENT_PENDING', 'money', await sc('settlements', 'passengerUid', ids, ['state'], stlActive));
  add('COURIER_ROUTE_ACTIVE', 'courier',
    await sc('delivery_routes', 'courierId', ids, ['status'], (d) => inList(A.routes, d.status)));

  // ── Қарзлар ва қўлдаги нақд (ledger_accounts, provider_capabilities)
  for (const id of ids) {
    const cash = await db.collection('ledger_accounts').doc(`courier_cash:${id}`).get();
    if (cash.exists && Number((cash.data() || {}).balance || 0) > 0) {
      out.push({ code: 'COURIER_CASH_HELD', area: 'courier', count: 1, sample: [cash.id] });
    }
    const flt = await db.collection('ledger_accounts').doc(`driver_float:${id}`).get();
    if (flt.exists && Number((flt.data() || {}).balance || 0) !== 0) {
      out.push({ code: 'DRIVER_FLOAT_NONZERO', area: 'courier', count: 1, sample: [flt.id] });
    }
  }
  for (const accountId of identity.accountIds) {
    const cap = await db.collection('provider_capabilities').doc(accountId).get();
    const debt = cap.exists ? Number(((cap.data() || {}).debt || {}).taxi || 0) : 0;
    if (debt > 0) out.push({ code: 'TAXI_DEBT', area: 'courier', count: 1, sample: [cap.id] });
  }

  // ── Пул ҳаракатда
  add('PAYOUT_PENDING', 'money',
    await sc('payout_requests', 'userPhone', ids, ['status'], (d) => inList(A.payout, d.status)));
  add('WITHDRAW_PENDING', 'money',
    await sc('wallet_withdraw_requests', 'uid', ids, ['status'], (d) => inList(A.withdraw, d.status)));
  add('TOPUP_PENDING', 'money',
    await sc('wallet_topup_requests', 'uid', ids, ['status'], (d) => inList(A.topup, d.status)));

  // Бир хил код такрорланса (икки сўров) битта қилиб, сонларни қўшамиз.
  const merged = new Map();
  for (const b of out) {
    const k = `${b.code}|${b.detail || ''}`;
    const cur = merged.get(k);
    if (!cur) merged.set(k, { ...b, sample: [...b.sample] });
    else {
      cur.count += b.count;
      cur.sample = [...cur.sample, ...b.sample].slice(0, 3);
    }
  }
  return [...merged.values()];
}

module.exports = {
  STAFF_ROLES, ACTIVE, SCAN_CAP, phoneForms, resolveIdentity, findBlockers,
};
