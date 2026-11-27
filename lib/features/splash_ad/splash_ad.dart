import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/uz_script.dart';

/// «Splash реклама» (эга 2026-11-28): илова очилишида 2 сония кўринадиган реклама ўрни.
///
/// Манба — `splash_ads/{id}` (ёзиш ФАҚАТ сервер: админ `adminUpsertSplashAd`, пуллик — модерациядан кейин
/// `adminModerateSplashAdOrder`; мижоз rules бўйича фақат `visible == true` ни ўқийди). Креативлар олдиндан
/// кешланади — очилишда тармоқ КУТИЛМАЙДИ ([SplashAdCache]); ҲАР очилишда навбатдагиси оғирлик бўйича
/// ([SplashAdRotation]).
class SplashAd {
  const SplashAd({
    required this.id,
    required this.version,
    this.text = const {},
    this.imageUrl = '',
    this.linkUrl = '',
    this.startAt,
    this.endAt,
    this.districts = const [],
    this.regionIds = const [],
    this.priority = 0,
    this.weight = 1,
  });

  final String id;

  /// Сервер версияси — кешдаги расм эскирганини билиш учун.
  final int version;

  /// `{uz_Cyrl, uz_Latn?, ru?}` — бўш бўлиши мумкин (фақат расм).
  final Map<String, String> text;
  final String imageUrl;

  /// Ихтиёрий `https://` ҳавола (креатив босилганда).
  final String linkUrl;
  final DateTime? startAt;
  final DateTime? endAt;

  /// Иккаласи бўш — бутун республика; акс ҳолда туман рўйхатда ЁКИ вилоят рўйхатда бўлсин.
  final List<String> districts;
  final List<String> regionIds;

  /// Эски майдон (айланишда ишлатилмайди).
  final int priority;

  /// Айланишдаги улуш: пуллик — кунига тўланган сумма, админ — админ белгилаган (эски ҳужжат — 1).
  final int weight;

  bool get hasImage => imageUrl.isNotEmpty;
  bool get hasText => (text['uz_Cyrl'] ?? '').isNotEmpty;
  bool get hasContent => hasImage || hasText;

  static int _weightOf(Object? v) {
    final w = v is num ? v.toInt() : 1;
    return w < 1 ? 1 : w;
  }

  static List<String> _list(Object? v) => [if (v is List) for (final x in v) '$x'];

  static SplashAd? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null || d['visible'] != true) return null;
    DateTime? at(Object? v) => v is Timestamp ? v.toDate() : null;
    return SplashAd(
      id: doc.id,
      version: (d['version'] as num?)?.toInt() ?? 1,
      text: _texts(d['text']),
      imageUrl: (d['imageUrl'] ?? '').toString().trim(),
      linkUrl: (d['linkUrl'] ?? '').toString().trim(),
      startAt: at(d['startAt']),
      endAt: at(d['endAt']),
      districts: _list(d['districts']),
      regionIds: _list(d['regionIds']),
      priority: (d['priority'] as num?)?.toInt() ?? 0,
      weight: _weightOf(d['weight']),
    );
  }

  /// Кеш шакли (SharedPreferences JSON).
  Map<String, Object?> toCacheMap() => {
        'id': id,
        'version': version,
        'text': text,
        'imageUrl': imageUrl,
        'linkUrl': linkUrl,
        'startAt': startAt?.millisecondsSinceEpoch,
        'endAt': endAt?.millisecondsSinceEpoch,
        'districts': districts,
        'regionIds': regionIds,
        'priority': priority,
        'weight': weight,
      };

  static SplashAd? fromCacheMap(Object? raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? '').toString();
    if (id.isEmpty) return null;
    DateTime? at(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return SplashAd(
      id: id,
      version: raw['version'] is int ? raw['version'] as int : 1,
      text: _texts(raw['text']),
      imageUrl: (raw['imageUrl'] ?? '').toString(),
      linkUrl: (raw['linkUrl'] ?? '').toString(),
      startAt: at(raw['startAt']),
      endAt: at(raw['endAt']),
      districts: _list(raw['districts']),
      regionIds: _list(raw['regionIds']),
      priority: raw['priority'] is int ? raw['priority'] as int : 0,
      weight: _weightOf(raw['weight']),
    );
  }

  static Map<String, String> _texts(Object? v) => {
        if (v is Map)
          for (final e in v.entries)
            if ('${e.value}'.trim().isNotEmpty) '${e.key}': '${e.value}'.trim(),
      };

  /// Сана ойнаси: `startAt ≤ now < endAt` (иккаласи ҳам мажбурий — сервер шундай ёзади).
  bool isInWindow(DateTime now) {
    final s = startAt;
    final e = endAt;
    if (s == null || e == null) return false;
    return !now.isBefore(s) && now.isBefore(e);
  }

  /// Ҳудуд: иккала рўйхат бўш — ҳамма; акс ҳолда қурилма тумани ёки вилояти рўйхатда.
  bool matchesArea(String districtId, [String regionId = '']) =>
      (districts.isEmpty && regionIds.isEmpty) ||
      (districtId.isNotEmpty && districts.contains(districtId)) ||
      (regionId.isNotEmpty && regionIds.contains(regionId));

  /// Эски ном (туман бўйича).
  bool matchesDistrict(String districtId) => matchesArea(districtId);

  bool isEligible(DateTime now, String districtId, [String regionId = '']) =>
      isInWindow(now) && matchesArea(districtId, regionId);

  /// Сервер сўрови учун ҳудуд калитлари (`areaKeys` array-contains-any): 'all', 'd:{туман}', 'r:{вилоят}'.
  static List<String> areaQueryKeys(String districtId, String regionId) => [
        'all',
        if (districtId.isNotEmpty) 'd:$districtId',
        if (regionId.isNotEmpty) 'r:$regionId',
      ];

  /// Кешга олинадиганлар: ҳудудга мос, тугамаган ва [horizon] ичида бошланадиган, мазмуни бор;
  /// оғирлиги каттаси олдин, кўпи билан [max] та.
  static List<SplashAd> selectForCache(
    Iterable<SplashAd> ads,
    DateTime now,
    String districtId,
    String regionId, {
    Duration horizon = const Duration(days: 2),
    int max = 8,
  }) {
    final out = [
      for (final a in ads)
        if (a.hasContent &&
            a.matchesArea(districtId, regionId) &&
            a.startAt != null &&
            a.endAt != null &&
            now.isBefore(a.endAt!) &&
            a.startAt!.isBefore(now.add(horizon)))
          a,
    ]..sort((a, b) => b.weight != a.weight ? b.weight.compareTo(a.weight) : a.id.compareTo(b.id));
    return out.take(max).toList();
  }

  /// Илова тилидаги матн; `uz_Latn` бўлмаса — кириллдан автоматик (янги лотин), `ru` бўлмаса — кирилл.
  String textFor(String lang) {
    final cyr = text['uz_Cyrl'] ?? '';
    switch (lang) {
      case 'uz_Latn':
        final l = text['uz_Latn'] ?? '';
        return l.isNotEmpty ? l : UzScript.toLatin(cyr);
      case 'ru':
        final r = text['ru'] ?? '';
        return r.isNotEmpty ? r : cyr;
      default:
        return cyr;
    }
  }
}

/// Smooth weighted round-robin (эга 2026-11-28: кўп тўлаган кўпроқ кўринади; кетма-кет очилишлар
/// имкон қадар турли реклама). Ҳолат — `{adId: currentWeight}`, қурилмада сақланади.
///
/// Ҳар қадам: ҳар номзод `cw += weight`; энг каттаси танланади; `cw[танланган] -= жами`. N = Σweight қадамда
/// ҳар реклама аниқ `weight` марта чиқади (бутун сонлар).
class SplashAdRotation {
  const SplashAdRotation._();

  /// Қайтаради: (танланган, янги ҳолат). Номзод йўқ — (null, {}). Ҳолатда фақат жорий номзодлар қолади.
  static (SplashAd?, Map<String, int>) next(List<SplashAd> candidates, Map<String, int> state) {
    if (candidates.isEmpty) return (null, const {});
    final list = [...candidates]..sort((a, b) => a.id.compareTo(b.id));
    final cw = <String, int>{};
    var total = 0;
    SplashAd? best;
    for (final a in list) {
      final v = (state[a.id] ?? 0) + a.weight;
      cw[a.id] = v;
      total += a.weight;
      if (best == null || v > cw[best.id]!) best = a;
    }
    cw[best!.id] = cw[best.id]! - total;
    return (best, cw);
  }
}

/// Splash матнлари (3 тил). Splash `MaterialApp`дан ТАШҚАРИДА чизилади (тил файллари ҳали юкланмаган
/// бўлиши мумкин) — шунинг учун матнлар шу ерда, `LocaleUtils.contentLangCode` бўйича танланади.
class SplashAdTexts {
  const SplashAdTexts._();

  static const Map<String, String> _placeholder = {
    'uz_Cyrl': 'Бу ерда сизнинг рекламангиз бўлиши мумкин',
    'uz_Latn': 'Bu yerda sizning reklamangiz bölişi mumkin',
    'ru': 'Здесь может быть ваша реклама',
  };
  static const Map<String, String> _advertise = {
    'uz_Cyrl': 'Реклама бериш',
    'uz_Latn': 'Reklama beriş',
    'ru': 'Разместить рекламу',
  };
  static const Map<String, String> _adLabel = {
    'uz_Cyrl': 'Реклама',
    'uz_Latn': 'Reklama',
    'ru': 'Реклама',
  };
  static const Map<String, String> _chatDraft = {
    'uz_Cyrl': 'Салом! Илова очилишидаги (splash) рекламани бермоқчиман.',
    'uz_Latn': 'Salom! Ilova oçilişidagi (splash) reklamani bermoqçiman.',
    'ru': 'Здравствуйте! Хочу разместить рекламу на заставке приложения.',
  };
  static const Map<String, String> _needLogin = {
    'uz_Cyrl': 'Реклама бериш учун рўйхатдан ўтинг.',
    'uz_Latn': "Reklama beriş uçun röyxatdan öting.",
    'ru': 'Чтобы разместить рекламу, зарегистрируйтесь.',
  };

  static String _of(Map<String, String> m, String lang) => m[lang] ?? m['uz_Cyrl']!;
  static String placeholder(String lang) => _of(_placeholder, lang);
  static String advertise(String lang) => _of(_advertise, lang);
  static String adLabel(String lang) => _of(_adLabel, lang);
  static String chatDraft(String lang) => _of(_chatDraft, lang);
  static String needLogin(String lang) => _of(_needLogin, lang);
}
