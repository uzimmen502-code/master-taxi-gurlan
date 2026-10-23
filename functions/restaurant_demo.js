/**
 * НАМУНА (demo) кафе-ресторанлар ва уй ошпазлари — эга қарори 2026-10-23: «3 та намуна кафе ва 3 та намуна уй
 * ошпази, ҳар бирига 5 тадан таом; дастлабки 3 та ҳақиқий субъект рўйхатдан ўтгунча кўрсат, кейин ўчириб ташла».
 *
 * Қоидалар (28, 16, 41-банд):
 *   - Ҳар намуна ҳужжатида `isDemo: true` (ёзади фақат Admin SDK; мижоз rules whitelist'ида йўқ).
 *   - Буюртма ТЎСИЛАДИ: `pausedUntil` узоқ келажакда → `placeRestaurantOrder` → `RESTAURANT_PAUSED` (сервер текшируви).
 *   - Телефон бўш (`contactPhone: ''`) — ҳеч ким «қўнғироқ қилиб» чалғитилмайди; эълон матни «намуна» дейди.
 *   - ID'лар аниқ (`demo_cafe_1…`, `demo_home_1…`) — қайта ишга тушириш такрор яратмайди.
 *   - АВТО-ЎЧИРИШ: тури бўйича (кафе / уй ошпази) ҳақиқий (isDemo эмас) тасдиқланган субъект сони ≥ 3 бўлса, шу
 *     турдаги намуналар ўчади (`restaurantDemoCleanup` триггери: restaurants/{rid} янги `approved` бўлганда).
 *     Ўчириш `admin_audit`га ёзилади (актор `system:demo_cleanup`). Идемпотент.
 *
 * Фақат бу файлдаги маълумот ва логика — бошқа ҳеч қандай модул ўзгармайди.
 */
'use strict';

const geoHash = require('./geo_hash');

const RESTAURANTS = 'restaurants';
const INDEX = 'restaurant_dish_index';
const ADMIN_AUDIT = 'admin_audit';
const DEMO_BATCH = 'demo-2026-10-23';
const REAL_THRESHOLD = 3;
const KINDS = Object.freeze(['cafe', 'home']);
/** `pausedUntil` — узоқ келажак: буюртма қабул қилинмайди. */
const PAUSED_UNTIL_ISO = '2099-01-01T00:00:00.000Z';
const OWNER_UID = 'demo_owner';
const NOTICE = 'Намуна · Namuna · Пример — буюртма қабул қилинмайди';

const CENTER = Object.freeze({ lat: 41.8442, lng: 60.3925 }); // Гурлан

function dish(name, description, price, servings, weightG) {
  return { name, description, price, servings, weightG };
}

/** Намуна маълумот тўплами (соф; тест ва tool ишлатади). */
const DEMO_SET = Object.freeze([
  {
    id: 'demo_cafe_1', kind: 'cafe', legalType: 'yatt', venueType: 'cafe',
    name: 'Бахор кафеси', address: 'Гурлан тумани, Мустақиллик кўчаси 12', cuisineTags: ['milliy'],
    description: 'Миллий таомлар ва иссиқ нонлар.', dLat: 0.0020, dLng: 0.0030,
    categories: ['Биринчи таомлар', 'Иккинчи таомлар'],
    dishes: [
      dish('Мастава', 'Гуручли, сабзавотли иссиқ шўрва', 22000, 1, 350),
      dish('Лағмон', 'Қўл чўзма, гўшт ва сабзавот билан', 32000, 1, 400),
      dish('Палов', 'Гўштли, сабзи ва нўхат билан', 38000, 1, 400),
      dish('Манти', '5 дона, қўй гўшти ва пиёз', 30000, 1, 300),
      dish('Қўй шашлиги', '2 сих, пиёз билан', 28000, 1, 220),
    ],
    cat: [0, 0, 1, 1, 1],
  },
  {
    id: 'demo_cafe_2', kind: 'cafe', legalType: 'yatt', venueType: 'chaikhana',
    name: 'Сайхун чойхонаси', address: 'Гурлан тумани, Навоий кўчаси 40', cuisineTags: ['milliy', 'shashlik'],
    description: 'Оилавий чойхона: шашлик ва қайноқ чой.', dLat: -0.0030, dLng: -0.0020,
    categories: ['Шашлик', 'Таомлар'],
    dishes: [
      dish('Сих кабоб', 'Мол гўшти, 2 сих', 26000, 1, 200),
      dish('Жиз-биз', 'Қўй гўшти, пиёз билан', 45000, 2, 500),
      dish('Шўрва', 'Қўй гўштли, картошкали', 30000, 1, 400),
      dish('Дамлама', 'Гўшт ва сабзавот дамланган', 42000, 2, 600),
      dish('Яшил чой', 'Чойнак, 2 киши учун', 8000, 2, 700),
    ],
    cat: [0, 0, 1, 1, 1],
  },
  {
    id: 'demo_cafe_3', kind: 'cafe', legalType: 'llc', venueType: 'cafe',
    name: 'Қўрғон фастфуд', address: 'Гурлан тумани, марказий бозор ёни', cuisineTags: ['fastfood', 'drinks'],
    description: 'Тез тайёрланадиган таомлар ва ичимликлар.', dLat: 0.0040, dLng: -0.0040,
    categories: ['Фастфуд', 'Ичимликлар'],
    dishes: [
      dish('Гамбургер', 'Мол гўштли котлет, сабзавот', 24000, 1, 260),
      dish('Чизбургер', 'Пишлоқ ва котлет билан', 27000, 1, 280),
      dish('Хот-дог', 'Қуймоқ нонда, соус билан', 15000, 1, 180),
      dish('Картошка фри', 'Катта порция', 14000, 2, 200),
      dish('Кока-кола 0.5 л', 'Совуқ ичимлик', 8000, 1, 500),
    ],
    cat: [0, 0, 0, 0, 1],
  },
  {
    id: 'demo_home_1', kind: 'home', legalType: 'individual', venueType: 'home',
    name: 'Зулфия опа — уй таомлари', address: 'Гурлан тумани, Янги ҳаёт МФЙ', cuisineTags: ['home', 'milliy'],
    description: 'Уйда тайёрланган таомлар, буюртма асосида.', dLat: 0.0015, dLng: -0.0035,
    categories: ['Уй таомлари', 'Нон ва ширинлик'],
    dishes: [
      dish('Уй палови', 'Ўз қўлимиз билан, гўштли', 35000, 1, 400),
      dish('Қозон кабоб', 'Картошка ва гўшт билан', 40000, 1, 450),
      dish('Дўлма', '6 дона, узум барги билан', 32000, 1, 350),
      dish('Тандир нон', '2 дона, иссиқ', 10000, 1, 300),
      dish('Чак-чак', 'Асалли, 500 г', 30000, 3, 500),
    ],
    cat: [0, 0, 0, 1, 1],
  },
  {
    id: 'demo_home_2', kind: 'home', legalType: 'individual', venueType: 'home',
    name: 'Моҳира опа ошхонаси', address: 'Гурлан тумани, Беруний кўчаси 7', cuisineTags: ['home'],
    description: 'Хамирли таомлар: сомса, манти, чучвара.', dLat: -0.0045, dLng: 0.0025,
    categories: ['Хамирли таомлар', 'Шўрвалар'],
    dishes: [
      dish('Тандир сомса', '4 дона, гўштли', 28000, 1, 400),
      dish('Чучвара', '20 дона, шўрвада', 30000, 1, 350),
      dish('Қовурма лағмон', 'Қўл чўзма, сабзавотли', 33000, 1, 420),
      dish('Мошхўрда', 'Мош ва гуруч, қатиқ билан', 24000, 1, 400),
      dish('Нўхат шўрва', 'Гўшт билан', 23000, 1, 400),
    ],
    cat: [0, 0, 0, 1, 1],
  },
  {
    id: 'demo_home_3', kind: 'home', legalType: 'individual', venueType: 'home',
    name: 'Дилнора — уй қандолатлари', address: 'Гурлан тумани, Гулистон кўчаси 3', cuisineTags: ['home', 'sweets'],
    description: 'Уйда пишириладиган торт ва ширинликлар.', dLat: 0.0050, dLng: 0.0010,
    categories: ['Тортлар', 'Ширинликлар'],
    dishes: [
      dish('Асалли торт', '1 кг, ўз рецептимиз', 120000, 8, 1000),
      dish('Наполеон торти', '1 кг', 110000, 8, 1000),
      dish('Қуруқ пирожний', '12 дона', 45000, 4, 500),
      dish('Хурмо ва ёнғоқли шарбат', 'Уй ширинлиги, 400 г', 38000, 3, 400),
      dish('Бахмал кекс', '6 бўлак', 36000, 3, 450),
    ],
    cat: [0, 0, 1, 1, 1],
  },
]);

const clamp = (n, a, b) => Math.min(b, Math.max(a, n));

/** Битта намунанинг Firestore ҳужжатлари (соф). `ts` — серверTimestamp ёки test Date. */
function buildDemoDocs(spec, { ts, pausedUntil }) {
  const lat = clamp(CENTER.lat + spec.dLat, -90, 90);
  const lng = clamp(CENTER.lng + spec.dLng, -180, 180);
  const restaurant = {
    name: spec.name,
    legalType: spec.legalType,
    venueType: spec.venueType,
    description: spec.description,
    cuisineTags: spec.cuisineTags,
    address: spec.address,
    contactPhone: '',
    lat, lng,
    geohash: geoHash.encode(lat, lng, 7),
    logoUrl: '', coverUrl: '', announcement: NOTICE,
    openingHours: { open: '09:00', close: '22:00' },
    prepTimeMin: 20,
    minOrderAmount: 0,
    delivery: {
      mode: 'none', pickup: true,
      ownFee: { type: 'fixed', fixed: 0, base: 0, perKm: 0, freeAbove: null, maxKm: null },
    },
    payment: { prepay: true, cash: true },
    pausedUntil,
    status: 'approved',
    ownerUid: OWNER_UID,
    ratingAvg: 0, ratingCount: 0, timeoutStreak: 0,
    createdAt: ts, updatedAt: ts, approvedAt: ts, approvedBy: 'system:demo_seed',
    isDemo: true, demoBatch: DEMO_BATCH,
  };
  const categories = spec.categories.map((name, i) => ({ id: `c${i + 1}`, data: { name, sort: i + 1, createdAt: ts, updatedAt: ts } }));
  const items = spec.dishes.map((d, i) => ({
    id: `d${i + 1}`,
    data: {
      name: d.name, description: d.description, price: d.price,
      categoryId: `c${spec.cat[i] + 1}`, sort: i + 1, available: true,
      servings: d.servings, weightG: d.weightG,
      createdAt: ts, updatedAt: ts,
    },
  }));
  return { restaurant, categories, items };
}

/** Тур: уй ошпази (`venueType: 'home'`) ёки кафе-ресторан (қолган ҳаммаси, эски ҳужжатлар ҳам). */
function kindOf(data) {
  return data && data.venueType === 'home' ? 'home' : 'cafe';
}

/**
 * Намуналар ўчадиган турларни ҳисоблайди: ҳақиқий (isDemo эмас) тасдиқланган сони ≥ [REAL_THRESHOLD].
 * 2 та count сўрови (бир нечта тенглик — composite индекс керак эмас) + `isDemo==true` рўйхати (кичик).
 */
async function evaluate(db) {
  const demoSnap = await db.collection(RESTAURANTS).where('isDemo', '==', true).get();
  const demos = demoSnap.docs.map((d) => ({ id: d.id, ref: d.ref, data: d.data() }));
  if (demos.length === 0) return { demos, real: null, kindsToRemove: [] };
  const approvedAll = (await db.collection(RESTAURANTS).where('status', '==', 'approved').count().get()).data().count;
  const approvedHome = (await db.collection(RESTAURANTS)
    .where('status', '==', 'approved').where('venueType', '==', 'home').count().get()).data().count;
  const demoApproved = demos.filter((d) => d.data.status === 'approved');
  const demoHome = demoApproved.filter((d) => kindOf(d.data) === 'home').length;
  const demoCafe = demoApproved.length - demoHome;
  const real = {
    home: approvedHome - demoHome,
    cafe: (approvedAll - approvedHome) - demoCafe,
  };
  const kindsToRemove = KINDS.filter((k) => real[k] >= REAL_THRESHOLD && demos.some((d) => kindOf(d.data) === k));
  return { demos, real, kindsToRemove };
}

/**
 * Ўчиради (идемпотент): аввал audit, сўнг ҳар намуна рекурсив (меню, категория, статистика), кейин индекс
 * ҳужжатлари. Қайтаради: { removed: [id...], real }.
 */
async function cleanupDemos(db, { admin, actor = 'system:demo_cleanup', reason = 'ҳақиқий субъектлар сони 3 тага етди' } = {}) {
  const { demos, real, kindsToRemove } = await evaluate(db);
  const victims = demos.filter((d) => kindsToRemove.includes(kindOf(d.data)));
  if (victims.length === 0) return { removed: [], real };
  await db.collection(ADMIN_AUDIT).add({
    kind: 'demo_restaurants_cleanup', actor, reason,
    removed: victims.map((v) => v.id), kinds: kindsToRemove, real,
    at: admin.firestore.FieldValue.serverTimestamp(),
  });
  for (const v of victims) {
    await db.recursiveDelete(v.ref);
    const stale = await db.collection(INDEX).where('restaurantId', '==', v.id).get();
    await Promise.all(stale.docs.map((x) => x.ref.delete()));
  }
  return { removed: victims.map((v) => v.id), real };
}

/** Триггер қарори: янги `approved` ва намуна эмас. Соф (тест учун). */
function shouldEvaluate(before, after) {
  if (!after) return false;
  if (after.isDemo === true) return false;
  if (after.status !== 'approved') return false;
  return !before || before.status !== 'approved';
}

function attachRestaurantDemoCleanup(exportsObj, deps) {
  const { functions, db, admin } = deps;
  exportsObj.restaurantDemoCleanup = functions.firestore
    .document('restaurants/{rid}')
    .onWrite(async (change, context) => {
      const before = change.before && change.before.exists ? change.before.data() : null;
      const after = change.after && change.after.exists ? change.after.data() : null;
      if (!shouldEvaluate(before, after)) return null;
      const t0 = Date.now();
      try {
        const out = await cleanupDemos(db, { admin });
        console.log(JSON.stringify({
          module: 'restaurant_demo', action: 'cleanup', restaurantId: context.params.rid,
          result: out.removed.length ? 'removed' : 'noop', removed: out.removed, real: out.real, durationMs: Date.now() - t0,
        }));
      } catch (e) {
        console.error(JSON.stringify({
          module: 'restaurant_demo', action: 'cleanup', restaurantId: context.params.rid, result: 'error',
          errorCode: 'DEMO_CLEANUP_FAILED', message: String((e && e.message) || e).slice(0, 200), durationMs: Date.now() - t0,
        }));
      }
      return null;
    });
}

module.exports = {
  attachRestaurantDemoCleanup, cleanupDemos, evaluate, shouldEvaluate, buildDemoDocs, kindOf,
  DEMO_SET, DEMO_BATCH, REAL_THRESHOLD, PAUSED_UNTIL_ISO, OWNER_UID, NOTICE, RESTAURANTS,
};
