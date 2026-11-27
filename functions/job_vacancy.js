/**
 * «ИШ ЎРИНЛАРИ — ВАКАНСИЯЛАР» (эга қарори 2026-11-28) — `submitJobAd` type 'work' нинг тузилмали шакли.
 *
 * Мавжуд `ads` занжири қайта ишлатилади (янги коллекция ЙЎҚ, 3/4-банд): вакансия = `ads/{id}` (type 'work')
 * + `vacancy` харитаси. Модерация, 30 кунлик муддат, ҳудуд ҳалқалари, шикоят — `ads` даги каби.
 * Фақат ИШ БЕРУВЧИ эълони: эски «Иш бор» (`work`) тури 2026-07 дан янги эълонда танланмасди; энди `work`
 * ФАҚАТ шу шакл билан қабул қилинади (эски APK `work` юбормайди — `AdKindX.userPanelKinds` = ad, service).
 *
 * `vacancy` (сервер ёзади, клиент ўзгартира олмайди — rules `adOwnerPatchOk` калит рўйхатида йўқ):
 *   v              1
 *   position       лавозим 3..80 (ҳужжат `title` ҳам шу)
 *   salaryFrom     бутун сўм (8-банд) 1..1 000 000 000, ихтиёрий
 *   salaryTo       бутун сўм, ихтиёрий; иккаласи бўлса from ≤ to
 *   salaryNegotiable  true — «Келишилади» (from/to сақланмайди)
 *   schedule       SCHEDULES дан бири
 *   experience     EXPERIENCE дан бири
 *   requirements   «Талаблар» 10..1000 — МАЖБУРИЙ, номзодга кўрсатилади
 *   employerKind / employerId / employerName / employerKey ('<kind>:<id>') — ихтиёрий, сервер текширади
 *   isFactory      иш берувчи — `manufacturing` турдаги бизнес объекти (завод саҳифаси шу калит билан ўқийди)
 *
 * Рўйхатлар ва чегаралар — PROPOSED (47-банд), эга тасдиқлагунча; Dart паритети:
 * lib/features/vacancies/domain/job_vacancy.dart (тест қулфлайди).
 *
 * Диагностика кодлари: VACANCY_REQUIRED, VACANCY_POSITION_INVALID, VACANCY_SALARY_INVALID,
 * VACANCY_SCHEDULE_INVALID, VACANCY_EXPERIENCE_INVALID, VACANCY_REQUIREMENTS_INVALID,
 * VACANCY_EMPLOYER_INVALID, VACANCY_DISTRICT_INVALID.
 */
'use strict';

const SCHEDULES = Object.freeze(['full_time', 'part_time', 'shift', 'remote', 'temporary']);
const EXPERIENCE = Object.freeze(['none', '1', '3', '5']);
const EMPLOYER_KINDS = Object.freeze(['business', 'restaurant', 'shop']);

const LIMITS = Object.freeze({
  positionMin: 3,
  positionMax: 80,
  requirementsMin: 10,
  requirementsMax: 1000,
  salaryMax: 1000000000,
});

/** Вакансия кўриниш муддати (кун) — бошқа эълонлар каби 30 (эга 2026-11-28). */
const VACANCY_EXPIRY_DAYS = 30;

const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const GEO_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;

function str(v, max) {
  return String(v == null ? '' : v).trim().slice(0, max);
}

/** Маош: бутун, мусбат, чегарада — бўлмаса `null`; йўқ (null/undefined/''/0) — `undefined`. */
function salaryOf(v) {
  if (v == null || v === '' || v === 0) return undefined;
  return Number.isSafeInteger(v) && v > 0 && v <= LIMITS.salaryMax ? v : null;
}

/**
 * Клиент `vacancy` харитасини текширади ва тозалайди (соф функция). Иш берувчи ва туман БУ ЕРДА ФАҚАТ шакл
 * бўйича текширилади — мавжудлиги/эгаси callable ичида (Firestore ўқиш).
 * `fail(code)` — хато ясовчи. → { vacancy, districtId }.
 */
function normalizeVacancy(raw, fail) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw fail('VACANCY_REQUIRED');
  const position = str(raw.position, LIMITS.positionMax + 1);
  if (position.length < LIMITS.positionMin || position.length > LIMITS.positionMax) {
    throw fail('VACANCY_POSITION_INVALID');
  }
  const negotiable = raw.salaryNegotiable === true;
  let salary = { salaryNegotiable: true };
  if (!negotiable) {
    const from = salaryOf(raw.salaryFrom);
    const to = salaryOf(raw.salaryTo);
    if (from === null || to === null || (from === undefined && to === undefined)
      || (from !== undefined && to !== undefined && from > to)) {
      throw fail('VACANCY_SALARY_INVALID');
    }
    salary = {
      salaryNegotiable: false,
      ...(from !== undefined ? { salaryFrom: from } : {}),
      ...(to !== undefined ? { salaryTo: to } : {}),
    };
  }
  const schedule = str(raw.schedule, 32);
  if (!SCHEDULES.includes(schedule)) throw fail('VACANCY_SCHEDULE_INVALID');
  const experience = str(raw.experience, 8);
  if (!EXPERIENCE.includes(experience)) throw fail('VACANCY_EXPERIENCE_INVALID');
  const requirements = str(raw.requirements, LIMITS.requirementsMax + 1);
  if (requirements.length < LIMITS.requirementsMin || requirements.length > LIMITS.requirementsMax) {
    throw fail('VACANCY_REQUIREMENTS_INVALID');
  }
  const employerKind = str(raw.employerKind, 16);
  const employerId = str(raw.employerId, 129);
  if (employerKind || employerId) {
    if (!EMPLOYER_KINDS.includes(employerKind) || !ID_RE.test(employerId)) throw fail('VACANCY_EMPLOYER_INVALID');
  }
  const districtId = str(raw.districtId, 65);
  if (districtId && !GEO_ID_RE.test(districtId)) throw fail('VACANCY_DISTRICT_INVALID');
  return {
    vacancy: {
      v: 1,
      position,
      ...salary,
      schedule,
      experience,
      requirements,
      ...(employerKind ? { employerKind, employerId } : {}),
    },
    districtId,
  };
}

function groupThousands(n) {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
}

/**
 * Эски иловалар учун `priceText` (улар `vacancy`ни билмайди) — кирилл, эски ёрлиқлар каби.
 * Янги илова маошни ўзи 3 тилда `salaryFrom/To` дан ясайди.
 */
function salaryText(v) {
  if (!v || v.salaryNegotiable === true) return 'Келишилади';
  const from = v.salaryFrom;
  const to = v.salaryTo;
  if (from && to) return from === to ? `${groupThousands(from)} сўм` : `${groupThousands(from)} – ${groupThousands(to)} сўм`;
  if (from) return `${groupThousands(from)} сўмдан`;
  if (to) return `${groupThousands(to)} сўмгача`;
  return 'Келишилади';
}

/** Иш берувчи калити — завод саҳифаси сўрови (`vacancy.employerKey ==`). */
function employerKeyOf(kind, id) {
  return kind && id ? `${kind}:${id}` : '';
}

module.exports = {
  SCHEDULES, EXPERIENCE, EMPLOYER_KINDS, LIMITS, VACANCY_EXPIRY_DAYS,
  normalizeVacancy, salaryText, employerKeyOf, groupThousands,
};
