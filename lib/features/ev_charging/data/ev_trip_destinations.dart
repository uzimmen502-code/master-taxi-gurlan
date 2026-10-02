// ⚡ EV сафар ёрдамчиси — манзил рўйхати.
//
// Нега қўлда ёзилган рўйхат: интерфейс максимал содда бўлиши керак —
// асосий савол «Қаерга борамиз?». Эркин матнни геокодлаш учун ҳар
// киритишда Google Geocoding сўрови керак бўлар эди; вилоят/шаҳар
// марказлари эса ўзгармайди, шунинг учун улар иловада турса — сўров
// йўқ, офлайн ишлайди ва бепул.
//
// Координаталар — шаҳар МАРКАЗИНИНГ тахминий нуқтаси. Аниқ кўча манзили
// эмас: Directions API уни энг яқин йўлга ўзи боғлайди, EV режаси учун
// эса бу аниқлик етарли (режа километрлар билан ишлайди, метрлар билан
// эмас).
//
// `UzbekistanPlaces` рўйхатидан фойдаланилмади — унда координата йўқ,
// фақат номлар бор.

class EvTripDestination {
  const EvTripDestination({
    required this.id,
    required this.nameCyrl,
    required this.nameLatn,
    required this.nameRu,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String nameCyrl;
  final String nameLatn;
  final String nameRu;
  final double lat;
  final double lng;

  /// Иловадаги тил кодига қараб ном (`uz_Cyrl` / `uz_Latn` / `ru`).
  String nameFor(String languageCode) => switch (languageCode) {
        'ru' => nameRu,
        'uz_Latn' => nameLatn,
        _ => nameCyrl,
      };

  /// Қидирувда учта ёзувнинг ҳаммаси бўйича мос келиш — фойдаланувчи
  /// «Samarqand» деб ёзса ҳам, «Самарқанд» деб ёзса ҳам топилади.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return nameCyrl.toLowerCase().contains(q) ||
        nameLatn.toLowerCase().contains(q) ||
        nameRu.toLowerCase().contains(q);
  }

  static const List<EvTripDestination> all = [
    EvTripDestination(
      id: 'tashkent',
      nameCyrl: 'Тошкент',
      nameLatn: 'Toshkent',
      nameRu: 'Ташкент',
      lat: 41.2995,
      lng: 69.2401,
    ),
    EvTripDestination(
      id: 'nukus',
      nameCyrl: 'Нукус',
      nameLatn: 'Nukus',
      nameRu: 'Нукус',
      lat: 42.4531,
      lng: 59.6103,
    ),
    EvTripDestination(
      id: 'urganch',
      nameCyrl: 'Урганч',
      nameLatn: 'Urganch',
      nameRu: 'Ургенч',
      lat: 41.5500,
      lng: 60.6333,
    ),
    EvTripDestination(
      id: 'xiva',
      nameCyrl: 'Хива',
      nameLatn: 'Xiva',
      nameRu: 'Хива',
      lat: 41.3783,
      lng: 60.3639,
    ),
    EvTripDestination(
      id: 'buxoro',
      nameCyrl: 'Бухоро',
      nameLatn: 'Buxoro',
      nameRu: 'Бухара',
      lat: 39.7747,
      lng: 64.4286,
    ),
    EvTripDestination(
      id: 'samarqand',
      nameCyrl: 'Самарқанд',
      nameLatn: 'Samarqand',
      nameRu: 'Самарканд',
      lat: 39.6542,
      lng: 66.9597,
    ),
    EvTripDestination(
      id: 'navoiy',
      nameCyrl: 'Навоий',
      nameLatn: 'Navoiy',
      nameRu: 'Навои',
      lat: 40.0844,
      lng: 65.3792,
    ),
    EvTripDestination(
      id: 'zarafshon',
      nameCyrl: 'Зарафшон',
      nameLatn: 'Zarafshon',
      nameRu: 'Зарафшан',
      lat: 41.5872,
      lng: 64.2017,
    ),
    EvTripDestination(
      id: 'uchquduq',
      nameCyrl: 'Учқудуқ',
      nameLatn: 'Uchquduq',
      nameRu: 'Учкудук',
      lat: 42.1569,
      lng: 63.5567,
    ),
    EvTripDestination(
      id: 'qarshi',
      nameCyrl: 'Қарши',
      nameLatn: 'Qarshi',
      nameRu: 'Карши',
      lat: 38.8606,
      lng: 65.7847,
    ),
    EvTripDestination(
      id: 'shahrisabz',
      nameCyrl: 'Шаҳрисабз',
      nameLatn: 'Shahrisabz',
      nameRu: 'Шахрисабз',
      lat: 39.0578,
      lng: 66.8306,
    ),
    EvTripDestination(
      id: 'termiz',
      nameCyrl: 'Термиз',
      nameLatn: 'Termiz',
      nameRu: 'Термез',
      lat: 37.2242,
      lng: 67.2783,
    ),
    EvTripDestination(
      id: 'jizzax',
      nameCyrl: 'Жиззах',
      nameLatn: 'Jizzax',
      nameRu: 'Джизак',
      lat: 40.1158,
      lng: 67.8422,
    ),
    EvTripDestination(
      id: 'guliston',
      nameCyrl: 'Гулистон',
      nameLatn: 'Guliston',
      nameRu: 'Гулистан',
      lat: 40.4897,
      lng: 68.7842,
    ),
    EvTripDestination(
      id: 'nurafshon',
      nameCyrl: 'Нурафшон',
      nameLatn: 'Nurafshon',
      nameRu: 'Нурафшан',
      lat: 41.0431,
      lng: 69.3611,
    ),
    EvTripDestination(
      id: 'chirchiq',
      nameCyrl: 'Чирчиқ',
      nameLatn: 'Chirchiq',
      nameRu: 'Чирчик',
      lat: 41.4689,
      lng: 69.5822,
    ),
    EvTripDestination(
      id: 'namangan',
      nameCyrl: 'Наманган',
      nameLatn: 'Namangan',
      nameRu: 'Наманган',
      lat: 40.9983,
      lng: 71.6726,
    ),
    EvTripDestination(
      id: 'andijon',
      nameCyrl: 'Андижон',
      nameLatn: 'Andijon',
      nameRu: 'Андижан',
      lat: 40.7821,
      lng: 72.3442,
    ),
    EvTripDestination(
      id: 'fargona',
      nameCyrl: 'Фарғона',
      nameLatn: 'Farg\'ona',
      nameRu: 'Фергана',
      lat: 40.3864,
      lng: 71.7864,
    ),
    EvTripDestination(
      id: 'qoqon',
      nameCyrl: 'Қўқон',
      nameLatn: 'Qo\'qon',
      nameRu: 'Коканд',
      lat: 40.5283,
      lng: 70.9425,
    ),
    EvTripDestination(
      id: 'margilon',
      nameCyrl: 'Марғилон',
      nameLatn: 'Marg\'ilon',
      nameRu: 'Маргилан',
      lat: 40.4714,
      lng: 71.7247,
    ),
  ];

  static List<EvTripDestination> search(String query) =>
      all.where((d) => d.matches(query)).toList();
}
