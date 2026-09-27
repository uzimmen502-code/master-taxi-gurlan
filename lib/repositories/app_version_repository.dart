import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/locale_utils.dart';

/// `app_config/version` ҳужжатининг ўқилган ҳолати.
class AppVersionConfig {
  const AppVersionConfig({
    required this.minSupportedBuild,
    required this.latestBuild,
    required this.message,
  });

  /// Шундан кичик build'лар мажбурий янгиланади. 0 = дарвоза ўчиқ.
  final int minSupportedBuild;

  /// Энг сўнгги build — юмшоқ эслатма учун. 0 = эслатма йўқ.
  final int latestBuild;

  /// Фойдаланувчи тилидаги матн. Бўш бўлса илова ўз таржимасини ишлатади.
  final String message;
}

/// Минимал версия конфигини ўқийди.
///
/// **Жойлашуви — `config/app_version`.** Атайлаб мавжуд `config`
/// коллекциясига қўйилган: унда аллақачон `allow read: if true;` ва
/// `allow write: if isAdmin();` қоидаси бор ([firestore.rules:1334]),
/// яъни янги қоида ёзиш ҳам, ДЕПЛОЙ ҚИЛИШ ҳам керак эмас. Ёнида
/// `config/module_defaults` турибди — бир хил намуна.
///
/// Ҳужжат ҚАСДАН оддий қилинган — эга уни Firestore консолидан қўлда
/// таҳрирлай олсин, релиз чиқармасдан:
///
/// ```json
/// config/app_version
/// {
///   "minSupportedBuild": 70,
///   "latestBuild": 73,
///   "message": {
///     "uz_Cyrl": "Илова янгиланди. Давом этиш учун янгиланг",
///     "uz_Latn": "Ilova yangilandi. Davom etish uchun yangilang",
///     "ru": "Приложение обновлено. Обновите для продолжения"
///   }
/// }
/// ```
class AppVersionRepository {
  AppVersionRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Ҳужжат йўқ бўлса `null` — бу ХАТО эмас, «дарвоза ҳали қўйилмаган»
  /// деган маъно. Чақирувчи уни очиқ деб қабул қилади.
  Future<AppVersionConfig?> fetch() async {
    final snap = await _db.collection('config').doc('app_version').get();
    if (!snap.exists) return null;
    final d = snap.data() ?? const <String, dynamic>{};
    return AppVersionConfig(
      minSupportedBuild: _asInt(d['minSupportedBuild']),
      latestBuild: _asInt(d['latestBuild']),
      message: await _pickMessage(d['message']),
    );
  }

  /// Сон бўлмаган ёки манфий қийматни 0 га айлантиради — яъни дарвоза
  /// ёпилмайди. Нотўғри терилган қиймат иловани ишдан чиқармасин.
  static int _asInt(dynamic v) {
    final n = v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    return n > 0 ? n : 0;
  }

  /// `message` — тил кодлари бўйича харита. Фойдаланувчи тилига мос
  /// келмаса бўш қайтади ва илова ўз локал таржимасини кўрсатади.
  static Future<String> _pickMessage(dynamic raw) async {
    if (raw is String) return raw.trim();
    if (raw is! Map) return '';
    final map = raw.map((k, v) => MapEntry('$k', '$v'));
    for (final key in await _localeKeys()) {
      final v = (map[key] ?? '').trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// Афзаллик тартиби: фойдаланувчи тили → ўзбек кирилл → рус.
  ///
  /// `effectiveLocale()` ҳар доим тил қайтаради (сақланган йўқ бўлса
  /// қурилма тилидан), шунинг учун `null` ҳолати йўқ.
  static Future<List<String>> _localeKeys() async {
    final out = <String>[];
    try {
      final loc = await LocaleUtils.effectiveLocale();
      final lang = loc.languageCode;
      final script = loc.scriptCode;
      if (script != null && script.isNotEmpty) out.add('${lang}_$script');
      out.add(lang);
    } catch (_) {
      // Тил аниқланмаса ҳам матн топилсин — пастдаги захира ишлайди.
    }
    out.addAll(const ['uz_Cyrl', 'uz', 'ru']);
    return out;
  }
}
