/// Рағбат туркумлари — ЯГОНА манба (эга 2026-11-02; 2026-11-28 бир жойга йиғилди).
///
/// Ишлатади: «AVA дўкони маҳсулотлари» формаси (маҳсулотнинг `incentiveCategory`си) ва «Рағбат дастурлари»
/// формаси (дастур `buckets[].category`). Калитлар сервер `CATEGORY_RE` (`^[a-z0-9_]{2,30}$`) га мос.
library;

/// Туркумсиз дастур ёки «исталган маҳсулот» тури (сервер `BUCKET_ANY` — ҳамма маҳсулотни қоплайди).
const String kIncentiveCategoryAny = 'any';

/// Маҳсулот туркумлари (тартиб — экрандаги тартиб).
const Map<String, String> kIncentiveCategories = {
  'tire': 'Шина',
  'oil': 'Мой',
  'battery': 'Аккумулятор',
  'insurance': 'Суғурта',
};

/// Дастур туркуми рўйхати: «Исталган маҳсулот» + маҳсулот туркумлари.
const Map<String, String> kIncentiveProgramCategories = {
  kIncentiveCategoryAny: 'Исталган маҳсулот',
  ...kIncentiveCategories,
};

/// Калит → кўрсатиладиган ном; рўйхатда йўқ (эски/бошқа) калит ўзи кўрсатилади.
String incentiveCategoryLabel(String key) => kIncentiveProgramCategories[key] ?? key;
