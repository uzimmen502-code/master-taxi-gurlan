/// «Кун янгиликлари»га автоматик белгилаш учун калит сўзлар (3 скрипт).
/// Фақат дўкон/витрина боғланмаган клипларга қўлланилади (publish screen'да).
const _tvNewsKeywords = [
  // uz_Cyrl
  'янгилик',
  'янгиликлар',
  'хабар',
  'воқеа',
  'ҳодиса',
  'фавқулодда',
  // uz_Latn
  'yangilik',
  'yangiliklar',
  'xabar',
  'voqea',
  'hodisa',
  'favqulodda',
  // ru
  'новост',
  'происшеств',
  'событ',
];

/// Сарлавҳа/тавсифда янгилик калит сўзи топилса `true`.
bool tvLooksLikeNews(String title, String description) {
  final text = '$title $description'.toLowerCase();
  return _tvNewsKeywords.any(text.contains);
}
