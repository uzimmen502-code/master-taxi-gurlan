/**
 * «Барча буюртмалар» — `order_index` (docs/barcha_buyurtmalar_taklifi_uz.md).
 *
 * Ҳар модул буюртмасига битта ҳужжат: ФАҚАТ ҲОЗИРГИ ҲОЛАТ (тарих манба
 * коллекцияларида қолади — 16-қоида). Ёзувчи — фақат шу ердаги триггерлар
 * ва backfill воситаси; клиент ёзолмайди (rules).
 *
 * Ягона манба (7, 44-қоида): модул статуси → умумий ҳолат (`normStatus`) +
 * босқич (`stage`) жадвали, иш вақти календари ва «тиқилиб қолган» вақти
 * (`stuckAt`) ШУ ФАЙЛДА ҳисобланади; экран фақат `now >= stuckAt` ни
 * солиштиради.
 *
 * Эга қарорлари: D-ALL-1…11 (2026-10-11). Чегара рақамлари — PROPOSED,
 * `settings/all_orders_stuck` орқали ўзгаради.
 */
'use strict';

const INDEX_COL = 'order_index';
const SETTINGS_DOC = ['settings', 'all_orders_stuck'];

/** Умумий ҳолатлар (экран тартиби). */
const NORM = {
  NEW: 'NEW',
  ACCEPTED: 'ACCEPTED',
  WAITING_COURIER: 'WAITING_COURIER',
  WITH_COURIER: 'WITH_COURIER',
  DELIVERED: 'DELIVERED',
  CANCELLED: 'CANCELLED',
  UNKNOWN: 'UNKNOWN',
};

const FINAL_NORM = new Set([NORM.DELIVERED, NORM.CANCELLED]);

// ─── Чегаралар (PROPOSED, D-ALL-4/7/8/10) ───────────────────────────────
// group: 'clock' — соат бўйича 24/7 (дақиқали жараён); 'work' — фақат иш
// вақти. Қоида: {min} — дақиқа; {workDays} — иш куни; {immediate};
// {prepPlusMin} — ресторан тайёрлаш вақти + N дақиқа.
// cycle — бутун жараён чегараси (`cycleSince`дан), босқичдан мустақил.
const DEFAULT_RULES = {
  bread: {
    group: 'clock',
    stages: {
      new: { min: 15 },
      accepted: { min: 60 },
      waiting_courier: { min: 20 },
      with_courier: { min: 60 },
    },
  },
  wholesale: {
    group: 'work',
    stages: { new: { min: 120 } },
    cycle: { workDays: 3, stages: ['accepted', 'waiting_courier', 'with_courier', 'waiting_pickup'] },
  },
  restaurant: {
    group: 'clock',
    // `placed` — 5 дақиқада сервер ўзи рад этади (ACCEPT_TIMEOUT_MIN).
    stages: {
      preparing: { prepPlusMin: 15 },
      waiting_courier: { min: 15 },
      with_courier: { min: 45 },
    },
  },
  carpet: {
    group: 'work',
    stages: {
      new: { min: 120 },
      pickup_wait: { min: 120 },
      pickup_transit: { min: 180 },
      ready_return: { workDays: 3 },
      return_transit: { min: 180 },
    },
    cycle: { workDays: 7, stages: ['processing', 'ready_return', 'return_transit'] },
  },
  milk: {
    group: 'work',
    stages: {
      new: { min: 120 },
      pickup_wait: { min: 120 },
      pickup_transit: { min: 180 },
      collected: { workDays: 1 },
    },
  },
  logistics: {
    group: 'work',
    stages: {
      leg_expired: { immediate: true },
      unassigned: { workDays: 1 },
      leg_accepted: { workDays: 1 },
      leg_local_transit: { workDays: 1 },
      leg_linehaul_transit: { workDays: 3 },
    },
    cycle: {
      workDays: 6,
      stages: ['unassigned', 'leg_accepted', 'leg_local_transit', 'leg_linehaul_transit', 'leg_expired'],
    },
  },
  courier: {
    group: 'clock',
    stages: {
      no_courier: { min: 15 },
      accepted: { min: 30 },
      in_progress: { min: 120 },
    },
  },
};

/** Иш вақти (PROPOSED; AVA'нинг ҳақиқий иш вақти — эга тасдиқлайди). */
const DEFAULT_CALENDAR = {
  tzOffsetMin: 300, // Asia/Tashkent, ёзги вақт йўқ
  days: [1, 2, 3, 4, 5, 6], // Душанба–Шанба (0 = Якшанба)
  startHour: 8,
  endHour: 20,
  holidays: [], // 'YYYY-MM-DD' (маҳаллий сана)
};

const MIN = 60 * 1000;
const DAY = 24 * 60 * MIN;

// ─── Календарь ──────────────────────────────────────────────────────────

function localParts(ms, cal) {
  const d = new Date(ms + cal.tzOffsetMin * MIN);
  const ymd = d.toISOString().slice(0, 10);
  const dayStartLocal = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
  return { dow: d.getUTCDay(), ymd, dayStartUtc: dayStartLocal - cal.tzOffsetMin * MIN };
}

function isWorkDay(ms, cal) {
  const p = localParts(ms, cal);
  return cal.days.includes(p.dow) && !(cal.holidays || []).includes(p.ymd);
}

/** Энг яқин иш вақти бошланиши (ичида бўлса — ўзи). */
function alignToWork(ms, cal) {
  let cursor = ms;
  for (let i = 0; i < 400; i += 1) {
    const p = localParts(cursor, cal);
    const open = p.dayStartUtc + cal.startHour * 60 * MIN;
    const close = p.dayStartUtc + cal.endHour * 60 * MIN;
    if (isWorkDay(cursor, cal)) {
      if (cursor < open) return open;
      if (cursor < close) return cursor;
    }
    cursor = p.dayStartUtc + DAY; // эртанги кун 00:00
  }
  throw new Error('calendar: work time not found');
}

/** [startMs] дан кейин [minutes] ИШ дақиқаси ўтган пайт. */
function addWorkMinutes(startMs, minutes, cal) {
  let remaining = minutes * MIN;
  let cursor = alignToWork(startMs, cal);
  for (let i = 0; i < 2000; i += 1) {
    const p = localParts(cursor, cal);
    const close = p.dayStartUtc + cal.endHour * 60 * MIN;
    const avail = close - cursor;
    if (remaining <= avail) return cursor + remaining;
    remaining -= avail;
    cursor = alignToWork(close, cal);
  }
  throw new Error('calendar: overflow');
}

/** [days] ИШ куни (кун вақти сақланади; бошланиш иш вақтига суралади). */
function addWorkDays(startMs, days, cal) {
  let cursor = alignToWork(startMs, cal);
  for (let n = 0; n < days; n += 1) {
    cursor += DAY;
    for (let g = 0; g < 30 && !isWorkDay(cursor, cal); g += 1) cursor += DAY;
  }
  return cursor;
}

function deadline(rule, sinceMs, group, cal, ctx = {}) {
  if (!rule || !Number.isFinite(sinceMs)) return null;
  if (rule.immediate) return sinceMs;
  if (Number.isFinite(rule.workDays)) return addWorkDays(sinceMs, rule.workDays, cal);
  let minutes = null;
  if (Number.isFinite(rule.min)) minutes = rule.min;
  if (Number.isFinite(rule.prepPlusMin)) {
    const prep = Number(ctx.prepTimeMin);
    minutes = (Number.isFinite(prep) && prep > 0 ? prep : 20) + rule.prepPlusMin;
  }
  if (minutes === null) return null;
  return group === 'work' ? addWorkMinutes(sinceMs, minutes, cal) : sinceMs + minutes * MIN;
}

// ─── Ҳолат жадвали ──────────────────────────────────────────────────────

function ms(v) {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number') return v;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  if (typeof v._seconds === 'number') return v._seconds * 1000 + Math.floor((v._nanoseconds || 0) / 1e6);
  return null;
}

function tail(phone) {
  const d = String(phone || '').replace(/\D/g, '');
  return d.length >= 4 ? d.slice(-4) : '';
}

function intOrNull(v) {
  const n = Number(v);
  return Number.isFinite(n) ? Math.round(n) : null;
}

const ORDER_STATUS = {
  new: [NORM.NEW, 'new'],
  accepted: [NORM.ACCEPTED, 'accepted'],
  ready: [NORM.WAITING_COURIER, 'waiting_courier'],
  in_delivery: [NORM.WITH_COURIER, 'with_courier'],
  courier: [NORM.WITH_COURIER, 'with_courier'], // эски ёзув, фақат ўқилади
  delivered: [NORM.DELIVERED, 'done'],
  rejected: [NORM.CANCELLED, 'cancelled'],
  cancelled: [NORM.CANCELLED, 'cancelled'],
};

const RESTAURANT_STATUS = {
  placed: [NORM.NEW, 'new'],
  accepted: [NORM.ACCEPTED, 'preparing'],
  ready: [NORM.WAITING_COURIER, 'waiting_courier'],
  picked: [NORM.WITH_COURIER, 'with_courier'],
  arrived: [NORM.WITH_COURIER, 'with_courier'],
  delivered: [NORM.DELIVERED, 'done'],
  rejected: [NORM.CANCELLED, 'cancelled'],
  cancelled: [NORM.CANCELLED, 'cancelled'],
  delivery_failed: [NORM.CANCELLED, 'cancelled'],
};

const CARPET_STATUS = {
  new: [NORM.NEW, 'new'],
  accepted: [NORM.ACCEPTED, 'pickup_wait'],
  pickup_ready: [NORM.WAITING_COURIER, 'pickup_wait'],
  pickup_in_delivery: [NORM.WITH_COURIER, 'pickup_transit'],
  picked_up: [NORM.ACCEPTED, 'processing'],
  washing: [NORM.ACCEPTED, 'processing'],
  drying: [NORM.ACCEPTED, 'processing'],
  ready: [NORM.ACCEPTED, 'ready_return'],
  return_ready: [NORM.WAITING_COURIER, 'ready_return'],
  return_in_delivery: [NORM.WITH_COURIER, 'return_transit'],
  delivered: [NORM.DELIVERED, 'done'],
  completed: [NORM.DELIVERED, 'done'],
  cancelled: [NORM.CANCELLED, 'cancelled'],
};

const MILK_STATUS = {
  new: [NORM.NEW, 'new'],
  accepted: [NORM.ACCEPTED, 'pickup_wait'],
  pickup_in_delivery: [NORM.WITH_COURIER, 'pickup_transit'],
  picked_up: [NORM.ACCEPTED, 'collected'],
  completed: [NORM.DELIVERED, 'done'],
  cancelled: [NORM.CANCELLED, 'cancelled'],
};

const DEMAND_STATUS = {
  draft: [NORM.NEW, 'draft'],
  active: [NORM.WAITING_COURIER, 'no_courier'],
  accepted: [NORM.ACCEPTED, 'accepted'],
  in_progress: [NORM.WITH_COURIER, 'in_progress'],
  completed: [NORM.DELIVERED, 'done'],
  cancelled: [NORM.CANCELLED, 'cancelled'],
  expired: [NORM.CANCELLED, 'cancelled'],
};

function pick(table, raw) {
  return table[raw] || [NORM.UNKNOWN, 'unknown'];
}

/**
 * Манба ҳужжатини умумий шаклга келтиради. `null` — индексга тушмайди
 * (масалан олиб ташланган `food`, бошқа модул талаби).
 */
function normalize(sourceCollection, d, extra = {}) {
  if (!d) return null;
  if (sourceCollection === 'orders') {
    const type = String(d.type || 'bread');
    if (type === 'food') return null; // «Овқат» олиб ташланди (2026-10-11)
    if (type === 'restaurant') {
      const raw = String(d.restaurantStatus || '');
      const [norm, stage] = pick(RESTAURANT_STATUS, raw);
      return {
        module: 'restaurant', normStatus: norm, stage, rawStatus: raw,
        courierId: d.courierId || null,
        amount: intOrNull(d.total),
        regionId: d.regionId || null, districtId: d.districtId || null,
        customerTail: tail(d.userPhone || d.phone),
        title: String(d.restaurantName || '').slice(0, 80),
        createdAtMs: ms(d.createdAt),
        statusTsMs: ms(d.statusUpdatedAt) || ms(d.updatedAt),
        ctx: { prepTimeMin: d.prepTimeMin },
      };
    }
    const raw = String(d.status || '');
    let [norm, stage] = pick(ORDER_STATUS, raw);
    const mode = String(d.fulfillmentMode || 'delivery');
    // Ўзи олиб кетади: «тайёр» — мижозни кутяпти, курьерни эмас.
    if (mode === 'pickup' && raw === 'ready') [norm, stage] = [NORM.ACCEPTED, 'waiting_pickup'];
    return {
      module: type === 'platform' ? 'wholesale' : 'bread',
      normStatus: norm, stage, rawStatus: raw,
      courierId: d.courierId || null,
      amount: intOrNull(d.total),
      regionId: d.regionId || null, districtId: d.districtId || null,
      customerTail: tail(d.userPhone || d.phone),
      title: mode === 'pos' ? 'POS' : '',
      createdAtMs: ms(d.createdAt),
      statusTsMs: ms(d.statusUpdatedAt) || ms(d.updatedAt),
      ctx: {},
    };
  }
  if (sourceCollection === 'carpet_wash_orders' || sourceCollection === 'agro_pickup_orders') {
    const carpet = sourceCollection === 'carpet_wash_orders';
    const raw = String(d.status || '');
    const [norm, stage] = pick(carpet ? CARPET_STATUS : MILK_STATUS, raw);
    const returning = stage === 'ready_return' || stage === 'return_transit';
    return {
      module: carpet ? 'carpet' : 'milk',
      normStatus: norm, stage, rawStatus: raw,
      courierId: (returning ? d.returnCourierId : d.pickupCourierId) || null,
      amount: carpet ? intOrNull(d.finalPrice) || null : null,
      regionId: d.regionId || null, districtId: d.districtId || null,
      customerTail: tail(d.customerPhone || d.customerId),
      title: '',
      createdAtMs: ms(d.createdAt),
      statusTsMs: ms(d.updatedAt),
      ctx: {},
    };
  }
  if (sourceCollection === 'shipments') {
    const raw = String(d.status || '');
    let norm;
    let stage;
    const assigned = d.legAssignments && Object.keys(d.legAssignments).length > 0;
    if (raw === 'awaiting_payment') [norm, stage] = [NORM.NEW, 'awaiting_payment'];
    else if (raw === 'delivered' || raw === 'closed') [norm, stage] = [NORM.DELIVERED, 'done'];
    else if (raw === 'cancelled') [norm, stage] = [NORM.CANCELLED, 'cancelled'];
    else if (raw === 'ready' || raw === 'in_transit') {
      if (d.legProblem && d.legProblem.kind) [norm, stage] = [NORM.WAITING_COURIER, 'leg_expired'];
      else if (raw === 'in_transit' && d.currentLegId) {
        const linehaul = extra.legKind === 'line_haul'
          || (extra.legKind === 'direct' && extra.legCrossRegion === true)
          || (!extra.legKind && extra.legCrossRegion !== false);
        [norm, stage] = [NORM.WITH_COURIER, linehaul ? 'leg_linehaul_transit' : 'leg_local_transit'];
      } else if (assigned) [norm, stage] = [NORM.WAITING_COURIER, 'leg_accepted'];
      else [norm, stage] = [NORM.WAITING_COURIER, 'unassigned'];
    } else [norm, stage] = [NORM.UNKNOWN, 'unknown'];
    const price = d.priceSnapshot || {};
    return {
      module: 'logistics', normStatus: norm, stage, rawStatus: raw,
      courierId: null,
      amount: intOrNull(price.customerPrice),
      regionId: (d.origin && d.origin.regionId) || null,
      districtId: (d.origin && d.origin.districtId) || null,
      customerTail: tail(d.ownerId),
      title: String(d.trackingNumber || '').slice(0, 40),
      createdAtMs: ms(d.createdAt),
      statusTsMs: (d.legProblem && ms(d.legProblem.at)) || ms(d.updatedAt),
      cycleStartMs: ms(d.fundedAt),
      ctx: {},
    };
  }
  if (sourceCollection === 'demands') {
    if (String(d.module || '') !== 'courier') return null; // LEG/бошқа модул — йўқ
    const raw = String(d.status || '');
    const [norm, stage] = pick(DEMAND_STATUS, raw);
    const budget = d.budget || {};
    return {
      module: 'courier', normStatus: norm, stage, rawStatus: raw,
      courierId: (d.assignment && d.assignment.providerId) || null,
      amount: intOrNull(budget.max !== undefined ? budget.max : budget.min),
      regionId: (d.location && d.location.regionId) || null,
      districtId: (d.location && d.location.districtId) || null,
      customerTail: tail(d.ownerId),
      title: '',
      createdAtMs: ms(d.createdAt),
      statusTsMs: ms(d.updatedAt),
      ctx: {},
    };
  }
  return null;
}

function mergeRules(override) {
  const out = JSON.parse(JSON.stringify(DEFAULT_RULES));
  const o = (override && override.rules) || {};
  for (const [mod, r] of Object.entries(o)) {
    if (!out[mod] || !r || typeof r !== 'object') continue;
    if (r.stages && typeof r.stages === 'object') Object.assign(out[mod].stages, r.stages);
    if (r.cycle && typeof r.cycle === 'object') out[mod].cycle = { ...(out[mod].cycle || {}), ...r.cycle };
  }
  return out;
}

function mergeCalendar(override) {
  const c = (override && override.calendar) || {};
  return {
    ...DEFAULT_CALENDAR,
    ...(Array.isArray(c.days) ? { days: c.days } : {}),
    ...(Number.isFinite(c.startHour) ? { startHour: c.startHour } : {}),
    ...(Number.isFinite(c.endHour) ? { endHour: c.endHour } : {}),
    ...(Array.isArray(c.holidays) ? { holidays: c.holidays.map(String) } : {}),
  };
}

/**
 * Индекс ҳужжати (вақтлар — миллисекунд). [prev] — мавжуд индекс (ms
 * майдонлар билан) ёки null. `stageSince` босқич ўзгармаса сақланади.
 */
function buildIndexDoc(prev, n, meta) {
  const rules = meta.rules || DEFAULT_RULES;
  const cal = meta.calendar || DEFAULT_CALENDAR;
  const modRules = rules[n.module] || { group: 'clock', stages: {} };
  const sameStage = prev && prev.stage === n.stage && prev.normStatus === n.normStatus;
  const fallbackSince = n.statusTsMs || n.createdAtMs || meta.eventMs;
  const stageSinceMs = sameStage && Number.isFinite(prev.stageSinceMs) ? prev.stageSinceMs : fallbackSince;

  const cycle = modRules.cycle;
  let cycleSinceMs = (prev && Number.isFinite(prev.cycleSinceMs)) ? prev.cycleSinceMs : null;
  if (cycleSinceMs === null && cycle && cycle.stages.includes(n.stage)) {
    cycleSinceMs = Number.isFinite(n.cycleStartMs) ? n.cycleStartMs : stageSinceMs;
  }

  const final = FINAL_NORM.has(n.normStatus);
  let stuckAtMs = null;
  let stuckRule = null;
  if (!final && n.normStatus !== NORM.UNKNOWN) {
    const a = deadline(modRules.stages[n.stage], stageSinceMs, modRules.group, cal, n.ctx);
    const b = cycle && cycle.stages.includes(n.stage) && cycleSinceMs !== null
      ? deadline({ workDays: cycle.workDays }, cycleSinceMs, 'work', cal)
      : null;
    if (a !== null && (b === null || a <= b)) [stuckAtMs, stuckRule] = [a, `stage:${n.stage}`];
    else if (b !== null) [stuckAtMs, stuckRule] = [b, 'cycle'];
  }

  return {
    module: n.module,
    sourceCollection: meta.sourceCollection,
    sourceId: meta.sourceId,
    normStatus: n.normStatus,
    stage: n.stage,
    rawStatus: n.rawStatus,
    final,
    courierId: n.courierId || null,
    hasCourier: !!n.courierId || ['with_courier', 'pickup_transit', 'return_transit',
      'in_progress', 'leg_accepted', 'leg_local_transit', 'leg_linehaul_transit'].includes(n.stage),
    amount: n.amount === undefined ? null : n.amount,
    regionId: n.regionId || null,
    districtId: n.districtId || null,
    customerTail: n.customerTail || '',
    title: n.title || '',
    createdAtMs: n.createdAtMs || stageSinceMs,
    stageSinceMs,
    cycleSinceMs,
    stuckAtMs,
    stuckRule,
    sinceApprox: !!meta.approx || (!sameStage && !n.statusTsMs),
    sourceUpdateMs: meta.updateMs || null,
  };
}

function indexDocId(module, sourceId) {
  return `${module}_${String(sourceId).replace(/[/\\]/g, '_')}`.slice(0, 700);
}

// ─── Firestore қатлами ──────────────────────────────────────────────────

function toFirestore(admin, doc) {
  const ts = (v) => (Number.isFinite(v) ? admin.firestore.Timestamp.fromMillis(v) : null);
  const { createdAtMs, stageSinceMs, cycleSinceMs, stuckAtMs, sourceUpdateMs, ...rest } = doc;
  return {
    ...rest,
    createdAt: ts(createdAtMs),
    stageSince: ts(stageSinceMs),
    cycleSince: ts(cycleSinceMs),
    stuckAt: ts(stuckAtMs),
    sourceUpdateTime: ts(sourceUpdateMs),
    indexedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function fromFirestore(d) {
  if (!d) return null;
  return {
    ...d,
    stageSinceMs: ms(d.stageSince),
    cycleSinceMs: ms(d.cycleSince),
    sourceUpdateMs: ms(d.sourceUpdateTime),
  };
}

let settingsCache = { at: 0, value: null };
async function loadSettings(db, now = Date.now()) {
  if (settingsCache.value && now - settingsCache.at < 5 * MIN) return settingsCache.value;
  let raw = null;
  try {
    const s = await db.collection(SETTINGS_DOC[0]).doc(SETTINGS_DOC[1]).get();
    raw = s.exists ? s.data() : null;
  } catch (e) {
    console.error(JSON.stringify({ action: 'orderIndexSettings', result: 'read_failed', error: String(e.message || e) }));
  }
  const value = { rules: mergeRules(raw), calendar: mergeCalendar(raw), version: (raw && raw.version) || 0 };
  settingsCache = { at: now, value };
  return value;
}

/** LEG тури (вилоятлараро ёки маҳаллий) — `demands/{currentLegId}`. */
async function legInfo(db, shipment) {
  if (!shipment || shipment.status !== 'in_transit' || !shipment.currentLegId) return {};
  try {
    const s = await db.collection('demands').doc(String(shipment.currentLegId)).get();
    if (!s.exists) return {};
    const d = s.data() || {};
    const a = (d.location && d.location.regionId) || '';
    const b = (d.destination && d.destination.regionId) || '';
    return {
      legKind: (d.attributes && d.attributes.legKind) || '',
      legCrossRegion: a && b ? a !== b : undefined,
    };
  } catch (_) {
    return {};
  }
}

/**
 * Битта манба ҳужжати учун индексни янгилайди (триггер ва backfill
 * умумий). Транзакцияда: эскирган ҳодиса (`updateTime` кичик) ёзилмайди.
 */
async function syncOne(db, admin, { sourceCollection, sourceId, data, updateMs, eventMs, approx = false, force = false }) {
  const settings = await loadSettings(db);
  const extra = sourceCollection === 'shipments' ? await legInfo(db, data) : {};
  const n = data ? normalize(sourceCollection, data, extra) : null;
  const moduleGuess = n ? n.module : null;
  const ids = n
    ? [indexDocId(n.module, sourceId)]
    : (sourceCollection === 'orders'
        ? ['bread', 'wholesale', 'restaurant'].map((m) => indexDocId(m, sourceId))
        : []);
  if (!n && sourceCollection !== 'orders') {
    // carpet/milk/shipments/courier — модул маълум.
    const mod = { carpet_wash_orders: 'carpet', agro_pickup_orders: 'milk', shipments: 'logistics', demands: 'courier' }[sourceCollection];
    if (mod) ids.push(indexDocId(mod, sourceId));
  }

  return db.runTransaction(async (t) => {
    const refs = ids.map((id) => db.collection(INDEX_COL).doc(id));
    const snaps = await Promise.all(refs.map((r) => t.get(r)));
    if (!n) {
      // Ўчирилди ёки индексга тушмайди (food, бошқа модул талаби).
      snaps.forEach((s, i) => { if (s.exists) t.delete(refs[i]); });
      return { action: 'removed', count: snaps.filter((s) => s.exists).length };
    }
    const prev = snaps[0].exists ? fromFirestore(snaps[0].data()) : null;
    // `force` — чегаралар ўзгарганда қайта ҳисоблаш (`--recompute`); манба
    // ўша ҳолатида, фақат `stuckAt` янгиланади.
    if (!force && prev && Number.isFinite(prev.sourceUpdateMs) && Number.isFinite(updateMs) && updateMs <= prev.sourceUpdateMs) {
      return { action: 'stale_skipped', module: moduleGuess };
    }
    const doc = buildIndexDoc(prev, n, {
      rules: settings.rules, calendar: settings.calendar,
      sourceCollection, sourceId, updateMs, eventMs, approx,
    });
    t.set(refs[0], { ...toFirestore(admin, doc), rulesVersion: settings.version });
    if (n.normStatus === NORM.UNKNOWN) {
      console.warn(JSON.stringify({
        action: 'orderIndex', result: 'unknown_status', module: n.module,
        sourceCollection, sourceId, rawStatus: n.rawStatus,
      }));
    }
    return { action: 'written', module: n.module, stage: n.stage };
  });
}

const SOURCES = ['orders', 'carpet_wash_orders', 'agro_pickup_orders', 'shipments', 'demands'];

function attachOrderIndex(exports, { db, admin }) {
  const { onDocumentWritten } = require('firebase-functions/v2/firestore');
  const make = (col, name) => {
    exports[name] = onDocumentWritten(
      { document: `${col}/{id}`, region: 'europe-west1' },
      async (event) => {
        const started = Date.now();
        const after = event.data && event.data.after;
        const exists = !!(after && after.exists);
        // Курьерга тегишли бўлмаган талаблар учун транзакция очмаймиз.
        if (col === 'demands' && exists && String((after.data() || {}).module || '') !== 'courier') return;
        try {
          const r = await syncOne(db, admin, {
            sourceCollection: col,
            sourceId: event.params.id,
            data: exists ? after.data() : null,
            updateMs: exists && after.updateTime ? ms(after.updateTime) : Date.parse(event.time),
            eventMs: Date.parse(event.time) || Date.now(),
          });
          if (r.action !== 'written') {
            console.log(JSON.stringify({ action: 'orderIndex', sourceCollection: col, sourceId: event.params.id, result: r.action, durationMs: Date.now() - started }));
          }
        } catch (e) {
          console.error(JSON.stringify({
            action: 'orderIndex', sourceCollection: col, sourceId: event.params.id,
            result: 'failed', errorCode: 'ORDER_INDEX_SYNC_FAILED', error: String(e.message || e),
            durationMs: Date.now() - started,
          }));
          throw e;
        }
      },
    );
  };
  make('orders', 'orderIndexOnOrders');
  make('carpet_wash_orders', 'orderIndexOnCarpet');
  make('agro_pickup_orders', 'orderIndexOnMilk');
  make('shipments', 'orderIndexOnShipments');
  make('demands', 'orderIndexOnDemands');
}

module.exports = {
  INDEX_COL, NORM, DEFAULT_RULES, DEFAULT_CALENDAR, SOURCES,
  normalize, buildIndexDoc, indexDocId, mergeRules, mergeCalendar,
  addWorkMinutes, addWorkDays, alignToWork, isWorkDay, deadline,
  syncOne, loadSettings, attachOrderIndex,
  _resetSettingsCache: () => { settingsCache = { at: 0, value: null }; },
};
