/**
 * ҲИСОБНИ ЎЧИРИШ — «дарҳол яшириш» ва қайтариш (эга қарори 7, docs/hisobni_ochirish_2026-10-24_uz.md §6).
 *
 * Сўров вақтида фойдаланувчининг ОЧИҚ контенти бошқаларга кўринмайдиган ҳолатга ўтказилади, ҳар ҳужжатнинг
 * олдинги қиймати `account_deletions/{uid}/hidden/{rule}__{docId}` га ёзилади. Бекор қилинса — ФАҚАТ биз
 * яшириб қўйганлар (ҳужжатда `hiddenByAccountDeletion: true` ва майдон ҳамон биз қўйган қиймат) қайтарилади;
 * админ ёки бошқа жараён орада ўзгартирган ҳужжатга тегилмайди.
 *
 * Яшириш майдонлари A1 таҳлилидан (2026-10-24, коддан): ҳар коллекцияда мавжуд механизм ишлатилади, янги
 * майдон ўйлаб топилмаган. Хавфсиз қиймат танлови (CONFIRMED, триггерлар текширилган):
 *  - ads → `inactive` (jobs ҳам, market ҳам; `onAdUpdate` фақат active/blocked/completed да хабар беради);
 *  - tv_clips → `expired` (`blocked` эгага «видео рад этилди» push юборади; `expired` триггерсиз);
 *  - tv_shop_items → `blocked`; yuk_listings → `closed`; wholesale_products → `inactive`;
 *  - realty_listings → `blocked` (қайтганда `onRealtyListingActivated` огоҳлантиришлари қайта юборилади — маълум);
 *  - ev_charging_stations, schedules, queue, intercity_drivers → `isActive:false`;
 *  - dating_profiles → `active:false` (триггер оммавий нусхани олиб ташлайди).
 * Қайтарилмайдиган/«яширишнинг тоза йўли йўқ» коллекциялар (businesses, tv_public_profiles, tv_shops,
 * wholesale_sellers, yuk_local_drivers, comments/likes) — ЯШИРИЛМАЙДИ, фақат якуний ўчиришда кетади (UNKNOWN→эгага айтилган).
 * Медиа URL лар 1 йил кэшланади, R2 feed 5–7 дақиқада янгиланади — «дарҳол» дегани шу кечикиш билан.
 */
'use strict';

const MAX_DOCS_PER_RULE = 5000;
const IN_CHUNK = 10;

/** keys: ids = identity.ids, forms = identity.forms, realty = identity.realtyOwnerKeys. mode 'query' | 'docId'. */
const HIDE_RULES = Object.freeze([
  { name: 'ads_market', col: 'ads', ownerField: 'ownerId', keys: 'ids', field: 'status', visible: ['active'], hideTo: 'inactive' },
  { name: 'ads_jobs', col: 'ads', ownerField: 'authorPhone', keys: 'forms', field: 'status', visible: ['active'], hideTo: 'inactive' },
  { name: 'tv_clips', col: 'tv_clips', ownerField: 'ownerPhone', keys: 'forms', field: 'status', visible: ['active'], hideTo: 'expired' },
  { name: 'tv_shop_items', col: 'tv_shop_items', ownerField: 'ownerPhone', keys: 'forms', field: 'status', visible: ['active'], hideTo: 'blocked' },
  { name: 'yuk_listings', col: 'yuk_listings', ownerField: 'ownerId', keys: 'ids', field: 'status', visible: ['active'], hideTo: 'closed' },
  { name: 'realty_listings', col: 'realty_listings', ownerField: 'ownerKey', keys: 'realty', field: 'status', visible: ['active'], hideTo: 'blocked' },
  { name: 'wholesale_products', col: 'wholesale_products', ownerField: 'sellerId', keys: 'ids', field: 'status', visible: ['active'], hideTo: 'inactive' },
  { name: 'ev_stations', col: 'ev_charging_stations', ownerField: 'createdBy', keys: 'ids', field: 'isActive', visible: [true], hideTo: false },
  { name: 'schedules', col: 'schedules', ownerField: 'driverId', keys: 'ids', field: 'isActive', visible: [true], hideTo: false },
  { name: 'queue', col: 'queue', mode: 'docId', field: 'isActive', visible: [true], hideTo: false },
  { name: 'intercity_drivers', col: 'intercity_drivers', mode: 'docId', field: 'isActive', visible: [true], hideTo: false },
  // dating: `active` майдони бўлмаса ҳам профил фаол ҳисобланади (active !== false)
  { name: 'dating_profiles', col: 'dating_profiles', mode: 'docId', field: 'active', visibleFn: (v) => v !== false, hideTo: false },
]);

const MARK = 'hiddenByAccountDeletion';
const hiddenRef = (db, uid, rule, id) => db.collection('account_deletions').doc(uid).collection('hidden').doc(`${rule}__${id}`);

const keysOf = (rule, identity) => {
  if (rule.keys === 'forms') return identity.forms;
  if (rule.keys === 'realty') return identity.realtyOwnerKeys;
  return identity.ids;
};

/**
 * deps: { db, admin, log? }. Қайтаради `{ name, hide(identity, ctx), unhide(identity, ctx) }` — `createAccountDeletion`
 * нинг `hiders` рўйхати учун ягона йиғинди ҳидер.
 */
function createHider(deps) {
  const { db, admin } = deps;
  const MAX_DOCS = deps.maxDocsPerRule || MAX_DOCS_PER_RULE;
  const FV = admin.firestore.FieldValue;
  const ts = () => FV.serverTimestamp();

  async function findVisible(rule, identity) {
    const found = [];
    const isVisible = rule.visibleFn || ((v) => rule.visible.includes(v));
    if (rule.mode === 'docId') {
      for (const id of [identity.d12, identity.d9]) {
        const s = await db.collection(rule.col).doc(id).get();
        if (s.exists && isVisible((s.data() || {})[rule.field])) found.push({ id, prev: (s.data() || {})[rule.field] });
      }
      return { found, partial: false };
    }
    const vals = [...new Set(keysOf(rule, identity))].filter(Boolean);
    let partial = false;
    for (let i = 0; i < vals.length; i += IN_CHUNK) {
      const snap = await db.collection(rule.col).where(rule.ownerField, 'in', vals.slice(i, i + IN_CHUNK))
        .select(rule.field).limit(MAX_DOCS + 1).get();
      if (snap.size > MAX_DOCS) partial = true;
      let n = 0;
      snap.forEach((d) => {
        n += 1;
        if (n > MAX_DOCS) return;
        const v = (d.data() || {})[rule.field];
        if (isVisible(v)) found.push({ id: d.id, prev: v });
      });
    }
    return { found, partial };
  }

  /** Идемпотент: аллақачон яширилган (қиймат hideTo) ҳужжат «кўринадиган»лар рўйхатига тушмайди — prev ўзгармайди. */
  async function hide(identity) {
    const uid = identity.d12;
    const result = { hidden: 0, partial: [] };
    for (const rule of HIDE_RULES) {
      const { found, partial } = await findVisible(rule, identity);
      if (partial) result.partial.push(rule.name);
      for (let i = 0; i < found.length; i += 200) {
        const b = db.batch();
        for (const f of found.slice(i, i + 200)) {
          const docRef = db.collection(rule.col).doc(f.id);
          // dating `active` йўқ бўлиши мумкин: prev ни null билан белгилаймиз (қайтаришда active:true қўямиз)
          b.set(hiddenRef(db, uid, rule.name, f.id), {
            rule: rule.name, col: rule.col, id: f.id, field: rule.field,
            prev: f.prev === undefined ? null : f.prev, hideTo: rule.hideTo, at: ts(), restored: false,
          });
          b.update(docRef, { [rule.field]: rule.hideTo, [MARK]: true });
        }
        await b.commit();
        result.hidden += Math.min(200, found.length - i);
      }
    }
    if (result.partial.length > 0) {
      const err = new Error(`HIDE_PARTIAL:${result.partial.join(',')}`);
      err.result = result;
      throw err;
    }
    return result;
  }

  /** Фақат биз яширганларни қайтаради; ўзгартирилганига тегмайди. */
  async function unhide(identity) {
    const uid = identity.d12;
    const snap = await db.collection('account_deletions').doc(uid).collection('hidden').where('restored', '==', false).get();
    let restored = 0;
    let skipped = 0;
    for (const rec of snap.docs) {
      const r = rec.data();
      const rule = HIDE_RULES.find((x) => x.name === r.rule);
      if (!rule) { skipped += 1; continue; }
      const docRef = db.collection(r.col).doc(r.id);
      await db.runTransaction(async (t) => {
        const cur = await t.get(docRef);
        const d = cur.exists ? (cur.data() || {}) : null;
        if (d && d[MARK] === true && d[r.field] === r.hideTo) {
          const back = r.prev === null && rule.name === 'dating_profiles' ? true : r.prev;
          t.update(docRef, { [r.field]: back === null ? FV.delete() : back, [MARK]: FV.delete() });
          restored += 1;
        } else {
          skipped += 1;
        }
        t.update(rec.ref, { restored: true, restoredAt: ts() });
      });
    }
    return { restored, skipped };
  }

  return {
    name: 'public_content',
    hide: (identity) => hide(identity),
    unhide: (identity) => unhide(identity),
    HIDE_RULES,
  };
}

module.exports = { createHider, HIDE_RULES, MARK };
