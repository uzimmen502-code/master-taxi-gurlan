/**
 * «МЕНИНГ БИЗНЕСИМ» МАҲСУЛОТ БУЮРТМАСИ — ҲОЛАТЛАР ЖАДВАЛИ (ягона манба, 7 ва 17-қоида).
 *
 * Соф модул (Firestore'сиз): `business_orders.js` (буюртма занжири) ва `delivery_failed.js`
 * («етказилмади» якуни) ШУ жадвални ишлатади — ҳолат номлари бошқа жойда ёзилмайди.
 * Айланма боғлиқлик бўлмаслиги учун алоҳида файл.
 *
 *   placed   → accepted | rejected | cancelled
 *   accepted → ready | rejected
 *   ready    → picked | rejected
 *   picked   → arrived | delivery_failed
 *   arrived  → delivered | delivery_failed
 *
 * Эски `status`/`fulfillmentStatus` (мавжуд «Буюртмалар» экрани, админ доскаси) — ресторан жадвали
 * билан бир хил кўзгу (`LEGACY`). Эски callable'лар (`courierListReadyOrders`, `courierCreateRoute`,
 * `courierSubmitPayment` …) `type: 'business'` буюртмани ЎТКАЗИБ ЮБОРАДИ / РАД ЭТАДИ (index.js гардлари).
 */
'use strict';

const ORDER_TYPE = 'business';

const BS = Object.freeze({
  placed: 'placed',
  accepted: 'accepted',
  ready: 'ready',
  picked: 'picked',
  arrived: 'arrived',
  delivered: 'delivered',
  rejected: 'rejected',
  cancelled: 'cancelled',
  deliveryFailed: 'delivery_failed',
});

const TRANSITIONS = Object.freeze({
  [BS.placed]: Object.freeze([BS.accepted, BS.rejected, BS.cancelled]),
  [BS.accepted]: Object.freeze([BS.ready, BS.rejected]),
  [BS.ready]: Object.freeze([BS.picked, BS.rejected]),
  [BS.picked]: Object.freeze([BS.arrived, BS.deliveryFailed]),
  [BS.arrived]: Object.freeze([BS.delivered, BS.deliveryFailed]),
  [BS.delivered]: Object.freeze([]),
  [BS.rejected]: Object.freeze([]),
  [BS.cancelled]: Object.freeze([]),
  [BS.deliveryFailed]: Object.freeze([]),
});

/** businessStatus → [status (эски), fulfillmentStatus] — ресторан `LEGACY` билан бир хил маъно. */
const LEGACY = Object.freeze({
  [BS.placed]: Object.freeze(['new', 'pending']),
  [BS.accepted]: Object.freeze(['accepted', 'confirmed']),
  [BS.ready]: Object.freeze(['ready', 'confirmed']),
  [BS.picked]: Object.freeze(['in_delivery', 'courier_picked']),
  [BS.arrived]: Object.freeze(['in_delivery', 'arrived']),
  [BS.delivered]: Object.freeze(['delivered', 'completed']),
  [BS.rejected]: Object.freeze(['rejected', 'cancelled']),
  [BS.cancelled]: Object.freeze(['cancelled', 'cancelled']),
  [BS.deliveryFailed]: Object.freeze(['cancelled', 'cancelled']),
});

/** Курьер қўлидаги (етказиш давом этаётган) ҳолатлар. */
const IN_DELIVERY = Object.freeze([BS.picked, BS.arrived]);
/** Курьер ола оладиган ҳолатлар (сотувчи қабул қилган, курьер йўқ). */
const CLAIMABLE = Object.freeze([BS.accepted, BS.ready]);
const FINAL = Object.freeze([BS.delivered, BS.rejected, BS.cancelled, BS.deliveryFailed]);

function isBusinessOrder(od) {
  return String((od && od.type) || '') === ORDER_TYPE;
}

function canTransition(from, to) {
  const allowed = TRANSITIONS[from];
  return !!allowed && allowed.includes(to);
}

/** Жорий ҳолат майдонлари (вақт белгиларисиз — уларни чақирувчи қўшади). */
function statusFields(bs) {
  const legacy = LEGACY[bs];
  if (!legacy) throw new Error(`business_order_states: unknown status ${bs}`);
  return { businessStatus: bs, status: legacy[0], fulfillmentStatus: legacy[1] };
}

module.exports = {
  ORDER_TYPE, BS, TRANSITIONS, LEGACY, IN_DELIVERY, CLAIMABLE, FINAL,
  isBusinessOrder, canTransition, statusFields,
};
