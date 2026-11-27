import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/uz_script.dart';

/// «Splash реклама» (эга 2026-11-28): илова очилишида 2 сония кўринадиган реклама ўрни.
///
/// Манба — `splash_ads/{id}` (ёзиш ФАҚАТ сервер: `adminUpsertSplashAd`/`adminDeleteSplashAd`, `admin_audit`;
/// мижоз rules бўйича фақат `visible == true` ни ўқийди). Креатив кейинги очилиш учун олдиндан кешланади —
/// очилишда тармоқ КУТИЛМАЙДИ ([SplashAdCache]).
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
    this.priority = 0,
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

  /// Бўш — барча туманлар.
  final List<String> districts;
  final int priority;

  bool get hasImage => imageUrl.isNotEmpty;

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
      districts: [if (d['districts'] is List) for (final x in d['districts'] as List) '$x'],
      priority: (d['priority'] as num?)?.toInt() ?? 0,
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
        'priority': priority,
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
      districts: [if (raw['districts'] is List) for (final x in raw['districts'] as List) '$x'],
      priority: raw['priority'] is int ? raw['priority'] as int : 0,
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

  /// Туман: рўйхат бўш — ҳамма; aks holda қурилма тумани маълум ва рўйхатда бўлсин.
  bool matchesDistrict(String districtId) =>
      districts.isEmpty || (districtId.isNotEmpty && districts.contains(districtId));

  bool isEligible(DateTime now, String districtId) => isInWindow(now) && matchesDistrict(districtId);

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

  /// Бир нечта мос реклама бўлса — энг юқори устуворлик, тенг бўлса энг кеч бошлангани.
  static SplashAd? pick(Iterable<SplashAd> ads, DateTime now, String districtId) {
    SplashAd? best;
    for (final a in ads) {
      if (!a.isEligible(now, districtId)) continue;
      if (a.imageUrl.isEmpty && (a.text['uz_Cyrl'] ?? '').isEmpty) continue;
      if (best == null ||
          a.priority > best.priority ||
          (a.priority == best.priority && a.startAt!.isAfter(best.startAt!))) {
        best = a;
      }
    }
    return best;
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
    'uz_Cyrl': 'Реклама бериш учун рўйхатдан ўтинг, кейин «Админ билан чат»га ёзинг.',
    'uz_Latn': "Reklama beriş uçun röyxatdan öting, keyin «Admin bilan çat»ga yozing.",
    'ru': 'Чтобы разместить рекламу, зарегистрируйтесь и напишите в «Чат с админом».',
  };

  static String _of(Map<String, String> m, String lang) => m[lang] ?? m['uz_Cyrl']!;
  static String placeholder(String lang) => _of(_placeholder, lang);
  static String advertise(String lang) => _of(_advertise, lang);
  static String adLabel(String lang) => _of(_adLabel, lang);
  static String chatDraft(String lang) => _of(_chatDraft, lang);
  static String needLogin(String lang) => _of(_needLogin, lang);
}
