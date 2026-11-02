import 'package:cloud_functions/cloud_functions.dart';

/// Рағбат таклифи (`getMyIncentiveOffers`, `functions/incentives.js`, эга қарори 2026-11-02).
class IncentiveOffer {
  const IncentiveOffer({
    required this.programId,
    required this.key,
    required this.title,
    required this.amount,
    this.buckets = const [],
    this.requireCar = false,
    this.claimed = false,
    this.eligible = false,
    this.needsCar = false,
    this.remaining = 0,
  });

  final String programId;
  final String key;

  /// `{uz_Cyrl, uz_Latn, ru}`.
  final Map<String, String> title;
  final int amount;

  /// `[{category, amount}]` — бўш: AVA дўконидаги исталган маҳсулот.
  final List<({String category, int amount})> buckets;
  final bool requireCar;
  final bool claimed;

  /// Ҳозир олиш мумкин (сервер шартлари бажарилган).
  final bool eligible;

  /// Фақат машина профили етишмайди — «машинангизни киритинг» таклифи.
  final bool needsCar;
  final int remaining;

  factory IncentiveOffer.fromMap(Map<dynamic, dynamic> m) {
    final t = m['title'] is Map ? (m['title'] as Map) : const {};
    final b = m['buckets'] is List ? (m['buckets'] as List) : const [];
    int i(Object? v) => v is num ? v.toInt() : 0;
    return IncentiveOffer(
      programId: '${m['programId'] ?? ''}',
      key: '${m['key'] ?? ''}',
      title: {for (final e in t.entries) '${e.key}': '${e.value}'},
      amount: i(m['amount']),
      buckets: [
        for (final x in b)
          if (x is Map) (category: '${x['category'] ?? ''}', amount: i(x['amount'])),
      ],
      requireCar: m['requireCar'] == true,
      claimed: m['claimed'] == true,
      eligible: m['eligible'] == true,
      needsCar: m['needsCar'] == true,
      remaining: i(m['remaining']),
    );
  }
}

/// Сервер билан алоқа. Тестларда алмаштирилади.
class IncentiveService {
  IncentiveService({FirebaseFunctions? functions}) : _functions = functions;
  final FirebaseFunctions? _functions;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  Future<List<IncentiveOffer>> myOffers() async {
    final res = await _fns.httpsCallable('getMyIncentiveOffers').call<Object?>(const {});
    final d = res.data;
    final list = d is Map && d['offers'] is List ? d['offers'] as List : const [];
    return [for (final o in list) if (o is Map) IncentiveOffer.fromMap(o)];
  }

  /// → берилган сумма (такрор бўлса ҳам — аввалги грант суммаси).
  Future<int> claim(String programId) async {
    final res = await _fns.httpsCallable('claimIncentive').call<Object?>({'programId': programId});
    final d = res.data;
    return d is Map && d['amount'] is num ? (d['amount'] as num).toInt() : 0;
  }
}

/// Таклифлардан нима қилиш кераклиги (соф функция — тест учун).
///  • [autoClaim] — машина шарт эмас, мос келади: ўзи олинади ва табрикланади (аёллар дастури);
///  • [carOffers] — машина дастури, ҳали олинмаган: «Олиш» сўралади (машина бўлмаса — аввал профиль).
({List<IncentiveOffer> autoClaim, List<IncentiveOffer> carOffers}) planIncentiveSteps(List<IncentiveOffer> offers) {
  return (
    autoClaim: [for (final o in offers) if (!o.claimed && o.eligible && !o.requireCar) o],
    carOffers: [for (final o in offers) if (!o.claimed && o.requireCar && (o.eligible || o.needsCar)) o],
  );
}
