import 'dart:io';

/// «Клиент ↔ сервер мослиги» тестлари СЕРВЕР КОД файлларини ўқийди
/// (`functions/restaurant_*.js`, `tv_clip_limits.js`, `firestore.rules` матни).
///
/// Муаммо (2026-10-21): hosting deploy-линияси чекаути фақат `lib|assets|test|web`
/// ни олади — `functions/` ва `firestore.rules` унда ЭСКИ ёки бутунлай йўқ.
/// Тестлар эса (ресторан бўлимлари, бронь, мавсум, таом видеоси…) линияга
/// кирган, шу сабабли линиянинг тўлиқ тест тўплами 14 та хато берарди
/// (`PathNotFoundException`, `Null check`, `Expected: contains …`) — тестлар
/// алоҳида ўтса ҳам. Хато клиентда ЭМАС, чекаутда эди.
///
/// Ечим: сервер манбалари тўлиқ бўлган чекаутда (feat/main) мослик тестлари
/// ҲАМИША қатъий ишлайди; тўлиқ бўлмаган deploy-линияда улар ёзилган сабаб
/// билан «skipped» бўлади (жимгина ўтиб кетмайди — ҳисоботда кўринади).
/// Сервер файли feat'да ўчирилса/номи ўзгарса — `server_parity_sentinel_test`
/// йиқилади.
const kServerParityFiles = <String>[
  'functions/restaurant_bookings.js',
  'functions/restaurant_dish_ratings.js',
  'functions/restaurant_preorder.js',
  'functions/restaurant_qty_tiers.js',
  'functions/restaurant_dish_index.js',
  'functions/restaurant_sections_config.js',
  'functions/restaurant_orders.js',
  'functions/tv_clip_limits.js',
  'functions/realty_video.js',
];

/// `functions/index.js` ресторан/видео сервер кодини ишлатадими (янги сервер).
/// Эски deploy-линия `index.js`ида бу сатр йўқ.
bool serverIndexIsCurrent() {
  try {
    return File('functions/index.js')
        .readAsStringSync()
        .contains("require('./tv_clip_limits')");
  } catch (_) {
    return false;
  }
}

/// Сервер манбалари ТЎЛИҚми (янги `index.js` + барча мослик файллари).
bool hasFullServerSources() =>
    serverIndexIsCurrent() && kServerParityFiles.every((f) => File(f).existsSync());

/// `test(..., skip: serverParitySkip)` учун: `null` — тест ишлайди.
final String? serverParitySkip = hasFullServerSources()
    ? null
    : 'сервер манба файллари тўлиқ эмас (hosting deploy-линияси чекаути) — '
        'мослик feat/main чекаутида текширилади';