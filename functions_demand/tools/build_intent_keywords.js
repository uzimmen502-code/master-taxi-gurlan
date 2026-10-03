/**
 * `assets/data/intent_keywords.json` НИ ТАКСОНОМИЯДАН ГЕНЕРАЦИЯ ҚИЛАДИ.
 *
 *   node functions_demand/tools/build_intent_keywords.js
 *
 * НЕГА ГЕНЕРАЦИЯ, НЕГА ҚЎЛДА ЁЗИЛМАЙДИ:
 * Intent Router (илова) ва `active_listings` манбаси (сервер) АЙНИ БИР
 * луғатни ишлатади. Иккита қўлда ёзилган нусха албатта ажралиб кетади —
 * фойдаланувчи «электрик керак» деб ёзганда илова тушунади, сервер эса
 * ўша одамни номзод деб топмайди (ёки тескариси).
 *
 * Шунинг учун ягона манба: `core/seed/taxonomy_services.json`.
 * Бу скрипт ундан иловага керакли КОМПАКТ шаклни ясайди:
 *   - калит сўзлар КАНОН (лотин) шаклда — илова инпутни ҳам шунга
 *     келтиради (`AdSearchText.toLatin`), шунда жадвал икки марта
 *     катталашмайди;
 *   - категория номлари учта тилда (UI учун);
 *   - кўп маъноли калитлар алоҳида.
 *
 * Файл ўзгарса `test/features/demand_offer/intent_router_test.dart`
 * синади — чунки у худди шу скрипт натижасини кутади.
 */
const fs = require('fs');
const path = require('path');

const { canonText, variants } = require('../core/text');

const ROOT = path.join(__dirname, '..', '..');
const SEED = path.join(__dirname, '..', 'core', 'seed', 'taxonomy_services.json');
const MODULES_SEED = path.join(__dirname, '..', 'core', 'seed', 'intent_modules.json');
const OUT = path.join(ROOT, 'assets', 'data', 'intent_keywords.json');

const taxonomy = JSON.parse(fs.readFileSync(SEED, 'utf8'));
const modulesSeed = JSON.parse(fs.readFileSync(MODULES_SEED, 'utf8'));

/** @type {Record<string, string[]>} канон калит -> категориялар */
const keywords = {};
/** @type {Record<string, {group: string, names: object}>} */
const categories = {};

for (const cat of taxonomy.categories) {
  categories[cat.id] = {
    group: cat.group || '',
    names: cat.names,
    unit: cat.unit || 'job',
    urgent: cat.urgent === true,
  };

  const phrases = [];
  for (const lang of ['uz_Cyrl', 'uz_Latn', 'ru']) {
    if (cat.names && cat.names[lang]) phrases.push(cat.names[lang]);
    if (cat.syn && Array.isArray(cat.syn[lang])) phrases.push(...cat.syn[lang]);
  }

  for (const phrase of phrases) {
    for (const v of variants(phrase)) {
      const key = canonText(v);
      if (key.length < 2) continue;
      if (!keywords[key]) keywords[key] = [];
      if (!keywords[key].includes(cat.id)) keywords[key].push(cat.id);
    }
  }
}

/** Кўп маъноли калитлар — канон шаклда. */
const ambiguous = {};
for (const entry of (taxonomy.ambiguous || [])) {
  for (const kw of (entry.keywords || [])) {
    for (const v of variants(kw)) {
      ambiguous[canonText(v)] = entry.categories;
    }
  }
}

// Барқарор тартиб — ҳар генерацияда бир хил файл чиқиши учун
// (акс ҳолда git diff ҳар сафар шовқин берарди).
const sortedKeywords = {};
for (const k of Object.keys(keywords).sort()) {
  sortedKeywords[k] = keywords[k].slice().sort();
}
const sortedCategories = {};
for (const k of Object.keys(categories).sort()) {
  sortedCategories[k] = categories[k];
}
const sortedAmbiguous = {};
for (const k of Object.keys(ambiguous).sort()) {
  sortedAmbiguous[k] = ambiguous[k].slice().sort();
}

/**
 * Умумий калитлар — «хизмат керак», лекин қайси хизмат номаълум.
 *
 * Эга мисоли: «Уста керак». Ҳеч қайси категорияга тушмайди, лекин
 * хизмат карточкаси кўрсатилиши ШАРТ (бошқа кириш нуқтаси йўқ).
 */
const generic = new Set();
for (const kw of (taxonomy.generic || [])) {
  for (const v of variants(kw)) {
    const key = canonText(v);
    if (key.length >= 2) generic.add(key);
  }
}
const sortedGeneric = Array.from(generic).sort();

/**
 * P0.3 — МОДУЛ ДАРАЖАСИДАГИ КАЛИТЛАР.
 *
 * Эга спецификацияси: қидирув «Курьер керак», «Тошкентга такси керак»,
 * «3 хонали квартира керак», «500 дона футболка керак» ни ҳам тушуниши
 * керак — фақат хизматни эмас.
 */
const moduleKeywords = {};
const moduleMeta = {};
for (const [moduleId, def] of Object.entries(modulesSeed.modules || {})) {
  moduleMeta[moduleId] = {
    label: def.label,
    coreReady: def.coreReady === true,
    existingScreen: def.existingScreen || null,
  };
  for (const kw of (def.keywords || [])) {
    for (const v of variants(kw)) {
      const key = canonText(v);
      if (key.length < 2) continue;
      if (!moduleKeywords[key]) moduleKeywords[key] = [];
      if (!moduleKeywords[key].includes(moduleId)) {
        moduleKeywords[key].push(moduleId);
      }
    }
  }
}
const sortedModuleKeywords = {};
for (const k of Object.keys(moduleKeywords).sort()) {
  sortedModuleKeywords[k] = moduleKeywords[k].slice().sort();
}

/**
 * Иш қидириш сўзлари — карточкани ТЎСАДИ.
 *
 * «курьер иш» = одам ўзи курьер бўлиб ишламоқчи, курьер керак эмас.
 */
const suppressWords = canonList(modulesSeed.suppressWords);

/** Ажратиб олиш намуналари — канон шаклда. */
const ex = modulesSeed.extract || {};
const extract = {
  quantityUnits: canonList(ex.quantityUnits),
  roomWords: canonList(ex.roomWords),
  destinations: (ex.destinations || []).map((d) => ({
    // Кўринадиган ном (форма учун) ва канон шакл (излаш учун).
    name: d,
    canon: canonText(d),
  })).sort((a, b) => a.canon.localeCompare(b.canon)),
};

function canonList(list) {
  const out = new Set();
  for (const item of (list || [])) {
    for (const v of variants(item)) {
      const key = canonText(v);
      if (key.length >= 1) out.add(key);
    }
  }
  return Array.from(out).sort();
}

const out = {
  _generated: 'functions_demand/tools/build_intent_keywords.js — QO\'LDA TAHRIRLANMAYDI',
  _source: 'functions_demand/core/seed/taxonomy_services.json '
    + '+ core/seed/intent_modules.json',
  version: taxonomy.version,
  module: taxonomy.module,
  /** Prefiks mosligi uchun minimal uzunlik — server bilan bir xil. */
  minPrefixLen: 4,
  /** Ko'p so'zli ibora vazni (yakka so'zdan ustun bo'lishi uchun). */
  phraseWeight: 3,
  categories: sortedCategories,
  ambiguous: sortedAmbiguous,
  /**
   * Умумий калитлар (канон). Топилса — хизмат карточкаси кўрсатилади,
   * лекин категория фойдаланувчи томонидан танланади.
   *
   * ДИҚҚАТ: таклифчи категориясини аниқлашда ИШЛАТИЛМАЙДИ.
   */
  generic: sortedGeneric,
  keywords: sortedKeywords,

  // ── P0.3 — модул даражаси ───────────────────────────────────────────
  /** канон калит → модуллар. */
  moduleKeywords: sortedModuleKeywords,
  /** модул → ном, ядрога уланганми, мавжуд экран. */
  modules: moduleMeta,
  /** Иш қидириш сўзлари — топилса карточка УМУМАН кўрсатилмайди. */
  suppressWords,
  /** Миқдор, хона сони, манзил ажратиш учун. */
  extract,
};

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, `${JSON.stringify(out, null, 2)}\n`, 'utf8');

const kwCount = Object.keys(sortedKeywords).length;
console.log(`Yozildi: ${path.relative(ROOT, OUT)}`);
console.log(`  kategoriya: ${Object.keys(sortedCategories).length}`);
console.log(`  kanon kalit: ${kwCount}`);
console.log(`  ko'p ma'noli: ${Object.keys(sortedAmbiguous).length}`);
console.log(`  umumiy kalit: ${sortedGeneric.length}`);
console.log(`  modul: ${Object.keys(moduleMeta).length}`);
console.log(`  modul kaliti: ${Object.keys(sortedModuleKeywords).length}`);
console.log(`  manzil: ${extract.destinations.length}`);
console.log(`  hajm: ${(fs.statSync(OUT).size / 1024).toFixed(1)} KB`);
