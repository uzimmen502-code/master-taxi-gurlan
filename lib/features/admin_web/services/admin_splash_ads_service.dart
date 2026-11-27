import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// «Splash реклама» — админ (эга 2026-11-28). Ёзиш ФАҚАТ сервер callable'лари орқали
/// (`functions/splash_ads.js`: `adminUpsertSplashAd` / `adminDeleteSplashAd`, `admin_audit`);
/// `splash_ads` ва `splash_ad_stats` ни админ rules бўйича ўқийди.
class AdminSplashAdsService {
  AdminSplashAdsService({FirebaseFunctions? functions, FirebaseFirestore? firestore})
      : _functions = functions,
        _firestore = firestore;

  final FirebaseFunctions? _functions;
  final FirebaseFirestore? _firestore;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAds() =>
      _db.collection('splash_ads').orderBy('priority', descending: true).limit(100).snapshots();

  /// Охирги 7 кунлик кўрсатишлар (кунлик йиғма ҳужжатлар `{adId}_{day}`).
  Future<int> impressionsLast7Days(String adId) async {
    final snap = await _db.collection('splash_ad_stats').where('adId', isEqualTo: adId).limit(60).get();
    final cutoff = DateTime.now().toUtc().add(const Duration(hours: 5)).subtract(const Duration(days: 7));
    final oldest = cutoff.toIso8601String().substring(0, 10);
    var sum = 0;
    for (final d in snap.docs) {
      final day = '${d.data()['day'] ?? ''}';
      final n = d.data()['impressions'];
      if (day.compareTo(oldest) >= 0 && n is num) sum += n.toInt();
    }
    return sum;
  }

  /// [ad] — сервер шакли (`title`, `text{uz_Cyrl,uz_Latn,ru}`, `imageUrl`, `linkUrl`, `startAtMs`, `endAtMs`,
  /// `districts`, `priority`, `active`, ихтиёрий `id`). → adId.
  Future<String> upsert(Map<String, Object?> ad, {String reason = ''}) async {
    final res = await _fns.httpsCallable('adminUpsertSplashAd').call<Object?>({'ad': ad, 'reason': reason});
    final d = res.data;
    return d is Map ? '${d['adId'] ?? ''}' : '';
  }

  Future<void> delete(String id, {String reason = ''}) async {
    await _fns.httpsCallable('adminDeleteSplashAd').call<Object?>({'id': id, 'reason': reason});
  }

  // ── Пуллик реклама: модерация, тариф, созлама ──

  /// Модерация навбати (rules: админ ўқийди). Тартиб — клиентда (композит индекс керак эмас).
  Stream<QuerySnapshot<Map<String, dynamic>>> watchOrders(String status) =>
      _db.collection('splash_ad_orders').where('status', isEqualTo: status).limit(100).snapshots();

  /// [decision]: `approve` | `reject` (рад — сабаб шарт, пул тўлиқ қайтади).
  Future<void> moderate(String orderId, String decision, {String reason = ''}) async {
    await _fns
        .httpsCallable('adminModerateSplashAdOrder')
        .call<Object?>({'orderId': orderId, 'decision': decision, 'reason': reason});
  }

  Future<Map<String, dynamic>> settings() async {
    final r = await _fns.httpsCallable('adminSplashAdGetSettings').call<Object?>({});
    return r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
  }

  Future<void> saveConfig({required String stage, required List<String> internalPhones, List<String> pilotDistrictIds = const []}) async {
    await _fns.httpsCallable('adminSplashAdSaveConfig').call<Object?>({
      'config': {'stage': stage, 'internalPhones': internalPhones, 'pilotDistrictIds': pilotDistrictIds},
    });
  }

  /// Янги ўзгармас тариф версияси (кунлик нарх, бутун сўм) → version.
  Future<int> publishTariff({required int district, required int region, required int republic, String note = ''}) async {
    final r = await _fns.httpsCallable('adminSplashAdPublishTariff').call<Object?>({
      'perDay': {'district': district, 'region': region, 'republic': republic},
      'note': note,
    });
    final d = r.data;
    return d is Map && d['version'] is num ? (d['version'] as num).toInt() : 0;
  }
}

/// Сервер хатоси → админ матни (админ панели кирилл, конвенция).
String splashAdAdminError(Object e) {
  if (e is FirebaseFunctionsException) {
    final det = e.details;
    final code = det is Map ? '${det['code'] ?? ''}' : '';
    final errors = det is Map && det['errors'] is List ? (det['errors'] as List).map((x) => '$x').toList() : <String>[];
    if (code == 'SPLASH_AD_INVALID') {
      const names = <String, String>{
        'title': 'номи (1–80 белги)',
        'content': 'расм ёки кирилл матн',
        'imageUrl': 'расм ҳаволаси (фақат юкланган расм)',
        'linkUrl': 'ҳавола (фақат https://)',
        'startAtMs': 'бошланиш санаси',
        'endAtMs': 'тугаш санаси',
        'window': 'муддат (тугаш бошланишдан кейин, ≤ 366 кун)',
        'districts': 'туман ID лари (кичик лотин, 50 тагача)',
        'regionIds': 'вилоят ID лари (кичик лотин)',
        'priority': 'устуворлик (0–100)',
        'weight': 'оғирлик (1 – 100 000 000)',
        'id': 'ID',
      };
      final list = errors.map((x) => names[x] ?? (x.startsWith('text.') ? 'матн (≤ 140 белги)' : x)).toSet().join(', ');
      return list.isEmpty ? 'Реклама маълумоти нотўғри.' : 'Текширинг: $list.';
    }
    if (e.code == 'permission-denied' || code == 'PERMISSION_DENIED') return 'Рухсат йўқ (фақат админ).';
    const known = <String, String>{
      'SPLASH_AD_PAID_READONLY': 'Пуллик рекламани бу ерда таҳрирлаб бўлмайди (модерация орқали).',
      'ORDER_EXPIRED': 'Муддати ўтиб кетган — рад этинг (пул тўлиқ қайтади).',
      'INVALID_TRANSITION': 'Буюртма аллақачон кўриб чиқилган.',
      'REASON_REQUIRED': 'Рад этиш сабабини ёзинг (камида 3 белги).',
      'ORDER_NOT_FOUND': 'Буюртма топилмади.',
      'TARIFF_INVALID': 'Нархлар бутун сон ва 0 дан катта бўлсин.',
      'CONFIG_INVALID': 'Созлама нотўғри (телефонлар 998… шаклида).',
    };
    if (known.containsKey(code)) return known[code]!;
  }
  return 'Амал бажарилмади. Қайта уриниб кўринг.';
}
