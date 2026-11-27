import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';

import '../ads/services/ads_storage_service.dart';

/// Пуллик splash реклама — мижоз хизмати (эга 2026-11-28). Нарх, тўлов, ҳолат — ФАҚАТ сервер
/// (`functions/splash_ads.js`): клиент нарх ҳисобламайди, фақат кўрсатади.
class SplashAdPurchaseInfo {
  const SplashAdPurchaseInfo({
    required this.available,
    this.durations = const [1, 3, 5, 7],
    this.perDay = const {},
    this.tariffVersion = 0,
    this.balance = 0,
    this.maxDistricts = 10,
    this.maxStartAheadDays = 60,
    this.today = '',
  });

  final bool available;
  final List<int> durations;

  /// Кунлик нарх даража бўйича: `district` (бир туман), `region`, `republic` — бутун сўм.
  final Map<String, int> perDay;
  final int tariffVersion;
  final int balance;
  final int maxDistricts;
  final int maxStartAheadDays;

  /// Сервер куни (Тошкент) `YYYY-MM-DD`.
  final String today;

  factory SplashAdPurchaseInfo.fromMap(Map m) => SplashAdPurchaseInfo(
        available: m['available'] == true,
        durations: [if (m['durations'] is List) for (final x in m['durations'] as List) if (x is num) x.toInt()],
        perDay: {
          if (m['perDay'] is Map)
            for (final e in (m['perDay'] as Map).entries)
              if (e.value is num) '${e.key}': (e.value as num).toInt(),
        },
        tariffVersion: (m['tariffVersion'] as num?)?.toInt() ?? 0,
        balance: (m['balance'] as num?)?.toInt() ?? 0,
        maxDistricts: (m['maxDistricts'] as num?)?.toInt() ?? 10,
        maxStartAheadDays: (m['maxStartAheadDays'] as num?)?.toInt() ?? 60,
        today: '${m['today'] ?? ''}',
      );
}

class SplashAdQuote {
  const SplashAdQuote({
    required this.amount,
    required this.pricePerDay,
    required this.balance,
    required this.sufficient,
    this.tariffVersion = 0,
  });

  final int amount;
  final int pricePerDay;
  final int balance;
  final bool sufficient;
  final int tariffVersion;

  factory SplashAdQuote.fromMap(Map m) => SplashAdQuote(
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        pricePerDay: (m['pricePerDay'] as num?)?.toInt() ?? 0,
        balance: (m['balance'] as num?)?.toInt() ?? 0,
        sufficient: m['sufficient'] == true,
        tariffVersion: (m['tariffVersion'] as num?)?.toInt() ?? 0,
      );
}

/// Харид сўрови (сервер шакли).
class SplashAdPurchaseRequest {
  const SplashAdPurchaseRequest({
    required this.clientRequestId,
    required this.days,
    required this.startDay,
    required this.areaLevel,
    this.districts = const [],
    this.regionId = '',
    this.imageUrl = '',
    this.text = '',
    this.linkUrl = '',
  });

  final String clientRequestId;
  final int days;
  final String startDay;
  final String areaLevel;
  final List<String> districts;
  final String regionId;
  final String imageUrl;
  final String text;
  final String linkUrl;

  Map<String, Object?> toMap() => {
        'clientRequestId': clientRequestId,
        'days': days,
        'startDay': startDay,
        'areaLevel': areaLevel,
        if (areaLevel == 'district') 'districts': districts,
        if (areaLevel == 'region') 'regionId': regionId,
        'creative': {'imageUrl': imageUrl, 'text': text, 'linkUrl': linkUrl},
      };
}

/// «Менинг рекламаларим» қатори.
class SplashAdOrderView {
  const SplashAdOrderView({
    required this.orderId,
    required this.status,
    required this.days,
    required this.startDay,
    required this.endDay,
    required this.areaLevel,
    this.districtCount = 0,
    this.amount = 0,
    this.impressions = 0,
    this.rejectReason = '',
    this.refundWallet = 0,
    this.imageUrl = '',
    this.text = '',
  });

  final String orderId;

  /// `pending` | `approved` | `rejected`.
  final String status;
  final int days;
  final String startDay;
  final String endDay;
  final String areaLevel;
  final int districtCount;
  final int amount;
  final int impressions;
  final String rejectReason;
  final int refundWallet;
  final String imageUrl;
  final String text;

  factory SplashAdOrderView.fromMap(Map m) => SplashAdOrderView(
        orderId: '${m['orderId'] ?? ''}',
        status: '${m['status'] ?? ''}',
        days: (m['days'] as num?)?.toInt() ?? 0,
        startDay: '${m['startDay'] ?? ''}',
        endDay: '${m['endDay'] ?? ''}',
        areaLevel: '${m['areaLevel'] ?? ''}',
        districtCount: m['districts'] is List ? (m['districts'] as List).length : 0,
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        impressions: (m['impressions'] as num?)?.toInt() ?? 0,
        rejectReason: '${m['rejectReason'] ?? ''}',
        refundWallet: m['refund'] is Map ? ((m['refund'] as Map)['wallet'] as num?)?.toInt() ?? 0 : 0,
        imageUrl: '${m['imageUrl'] ?? ''}',
        text: '${m['text'] ?? ''}',
      );
}

/// Сервер хатоси (фойдаланувчи матни 3 тилда сервердан; ички код — `code`).
class SplashAdPurchaseError implements Exception {
  const SplashAdPurchaseError(this.code, {this.messages = const {}, this.amount});

  final String code;
  final Map<String, String> messages;

  /// PRICE_CHANGED — янги нарх.
  final int? amount;

  String messageFor(String lang, String fallback) => messages[lang] ?? messages['uz_Cyrl'] ?? fallback;
}

class SplashAdPurchaseService {
  SplashAdPurchaseService({FirebaseFunctions? functions, AdsStorageService? storage})
      : _functions = functions,
        _storage = storage;

  final FirebaseFunctions? _functions;
  final AdsStorageService? _storage;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  Future<Map> _call(String name, [Map<String, Object?> data = const {}]) async {
    try {
      final r = await _fns.httpsCallable(name).call<Object?>(data);
      return r.data is Map ? r.data as Map : const {};
    } on FirebaseFunctionsException catch (e) {
      final d = e.details;
      throw SplashAdPurchaseError(
        d is Map ? '${d['code'] ?? e.code}' : e.code,
        messages: {
          if (d is Map && d['messages'] is Map)
            for (final x in (d['messages'] as Map).entries) '${x.key}': '${x.value}',
        },
        amount: d is Map && d['amount'] is num ? (d['amount'] as num).toInt() : null,
      );
    }
  }

  Future<SplashAdPurchaseInfo> getInfo() async => SplashAdPurchaseInfo.fromMap(await _call('splashAdGetPurchaseInfo'));

  Future<SplashAdQuote> quote(SplashAdPurchaseRequest r) async => SplashAdQuote.fromMap(await _call('splashAdQuote', r.toMap()));

  /// → orderId. Бир хил `clientRequestId` қайта юборилса — сервер қайта ечмайди.
  Future<String> purchase(SplashAdPurchaseRequest r, {required int expectedAmount}) async {
    final m = await _call('splashAdPurchase', {...r.toMap(), 'expectedAmount': expectedAmount});
    return '${m['orderId'] ?? ''}';
  }

  Future<List<SplashAdOrderView>> myOrders() async {
    final m = await _call('splashAdListMyOrders');
    return [
      if (m['orders'] is List)
        for (final o in m['orders'] as List)
          if (o is Map) SplashAdOrderView.fromMap(o),
    ];
  }

  /// Расм — мавжуд `ads/{телефон}/` папкасига (Storage rules: фақат ўз папкаси, ≤ 8 МБ, расм).
  Future<String> uploadImage({required String ownerPhone, required XFile image}) async {
    final urls = await (_storage ?? AdsStorageService()).uploadImages(ownerId: ownerPhone, images: [image]);
    return urls.first;
  }
}
