import 'package:cloud_functions/cloud_functions.dart';

/// «Автомобил суғуртаси» (эга 2026-11-28) — сервер `functions/car_insurance.js` билан алоқа. Нарх, чегирма,
/// тўлов ва ҳолат — фақат серверда (44-банд); илова кўрсатади ва танловни юборади.

int _i(Object? v) => v is num ? v.toInt() : 0;
String _s(Object? v) => v == null ? '' : '$v';

/// Ҳолатлар (сервер `STATUSES`).
const kInsuranceStatuses = ['requested', 'paid', 'in_progress', 'issued', 'cancelled'];

/// Транспорт тоифалари (сервер `VEHICLE_TYPES`; эга ОСАГО жадвали 2026-11-28): car — Енгил автомобил, truck — Юк
/// автомобили, bus — Микроавтобус, moto — Трактор ва мотоцикл.
const kInsuranceVehicleTypes = ['car', 'truck', 'bus', 'moto'];

/// Нарх ҳудудлари (сервер `ZONES`): tashkent — Тошкент ш. ва вилояти, other — бошқа ҳудудлар, cis — МДҲ рақамли.
const kInsuranceZones = ['tashkent', 'other', 'cis'];

/// Ҳайдовчилар (сервер `DRIVER_SCOPES`): limited — Чекланган, unlimited — Чекланмаган.
const kInsuranceDriverScopes = ['limited', 'unlimited'];

class InsuranceOption {
  const InsuranceOption({
    required this.policyType,
    required this.vehicleType,
    required this.termMonths,
    required this.price,
    this.zone = '',
    this.driverScope = '',
  });
  final String policyType;
  final String vehicleType;
  final int termMonths;
  final int price;

  /// schema 2 жадвалида (бўш — эски вилоят жадвали).
  final String zone;
  final String driverScope;

  factory InsuranceOption.fromMap(Map m) => InsuranceOption(
        policyType: _s(m['policyType']),
        vehicleType: _s(m['vehicleType']),
        termMonths: _i(m['termMonths']),
        price: _i(m['price']),
        zone: _s(m['zone']),
        driverScope: _s(m['driverScope']),
      );
}

class InsuranceOilStep {
  const InsuranceOilStep(this.count, this.pct);
  final int count;
  final int pct;
}

class InsuranceCampaign {
  const InsuranceCampaign({
    required this.year,
    required this.bonusEnabled,
    required this.bonusAmount,
    required this.bonusValidityDays,
    required this.oilEnabled,
    required this.oilSteps,
  });
  final int year;
  final bool bonusEnabled;
  final int bonusAmount;
  final int bonusValidityDays;
  final bool oilEnabled;
  final List<InsuranceOilStep> oilSteps;

  factory InsuranceCampaign.fromMap(Map m) => InsuranceCampaign(
        year: _i(m['year']),
        bonusEnabled: m['bonusEnabled'] == true,
        bonusAmount: _i(m['bonusAmount']),
        bonusValidityDays: _i(m['bonusValidityDays']),
        oilEnabled: m['oilEnabled'] == true,
        oilSteps: [
          for (final s in (m['oilSteps'] is List ? m['oilSteps'] as List : const []))
            if (s is Map) InsuranceOilStep(_i(s['count']), _i(s['pct'])),
        ],
      );
}

class InsuranceEnrollment {
  const InsuranceEnrollment({
    required this.year,
    required this.option,
    required this.plate,
    required this.oilChanges,
    required this.oilGoal,
    required this.discountPct,
    required this.discountUsed,
  });
  final int year;
  final String option;
  final String plate;
  final int oilChanges;
  final int oilGoal;
  final int discountPct;
  final bool discountUsed;

  factory InsuranceEnrollment.fromMap(Map m) => InsuranceEnrollment(
        year: _i(m['year']),
        option: _s(m['option']),
        plate: _s(m['plate']),
        oilChanges: _i(m['oilChanges']),
        oilGoal: _i(m['oilGoal']),
        discountPct: _i(m['discountPct']),
        discountUsed: m['discountUsed'] == true,
      );
}

class InsuranceState {
  const InsuranceState({
    required this.available,
    this.kaskoEnabled = false,
    this.options = const [],
    this.tariffVersion = 0,
    this.tariffSchema = 1,
    this.derivedZone = 'other',
    this.carModel = '',
    this.carBrand = '',
    this.carPlate = '',
    this.carYear = 0,
    this.carComplete = false,
    this.expiresOn = '',
    this.policyType = '',
    this.expirySource = '',
    this.remindersOptIn = true,
    this.campaign,
    this.enrollment,
  });
  final bool available;
  final bool kaskoEnabled;
  final List<InsuranceOption> options;
  final int tariffVersion;

  /// 2 — ҳудуд × тоифа × ҳайдовчи жадвали (эга 2026-11-28); 1 — эски вилоят жадвали.
  final int tariffSchema;

  /// Профил туманидан (сервер): tashkent | other.
  final String derivedZone;
  final String carModel;
  final String carBrand;
  final String carPlate;
  final int carYear;
  final bool carComplete;

  /// 'YYYY-MM-DD' ёки бўш.
  final String expiresOn;
  final String policyType;
  final String expirySource;
  final bool remindersOptIn;
  final InsuranceCampaign? campaign;
  final InsuranceEnrollment? enrollment;

  static const unavailable = InsuranceState(available: false);

  factory InsuranceState.fromMap(Map m) {
    final car = m['car'] is Map ? m['car'] as Map : const {};
    final ci = m['carInsurance'] is Map ? m['carInsurance'] as Map : const {};
    return InsuranceState(
      available: m['available'] == true,
      kaskoEnabled: m['kaskoEnabled'] == true,
      options: [
        for (final o in (m['options'] is List ? m['options'] as List : const []))
          if (o is Map) InsuranceOption.fromMap(o),
      ],
      tariffVersion: _i(m['tariffVersion']),
      tariffSchema: m['tariffSchema'] is num ? (m['tariffSchema'] as num).toInt() : 1,
      derivedZone: m['derivedZone'] == 'tashkent' ? 'tashkent' : 'other',
      carModel: _s(car['model']),
      carBrand: _s(car['brand']),
      carPlate: _s(car['plate']),
      carYear: _i(car['year']),
      carComplete: car['complete'] == true,
      expiresOn: _s(ci['expiresOn']),
      policyType: _s(ci['policyType']),
      expirySource: _s(ci['source']),
      remindersOptIn: m['remindersOptIn'] != false,
      campaign: m['campaign'] is Map ? InsuranceCampaign.fromMap(m['campaign'] as Map) : null,
      enrollment: m['enrollment'] is Map ? InsuranceEnrollment.fromMap(m['enrollment'] as Map) : null,
    );
  }
}

class InsuranceQuote {
  const InsuranceQuote({
    required this.price,
    required this.oilPct,
    required this.oilDiscount,
    required this.incentive,
    required this.walletDue,
    required this.walletBalance,
    required this.sufficient,
  });
  final int price;
  final int oilPct;
  final int oilDiscount;
  final int incentive;
  final int walletDue;
  final int walletBalance;
  final bool sufficient;

  factory InsuranceQuote.fromMap(Map m) => InsuranceQuote(
        price: _i(m['price']),
        oilPct: _i(m['oilPct']),
        oilDiscount: _i(m['oilDiscount']),
        incentive: _i(m['incentive']),
        walletDue: _i(m['walletDue']),
        walletBalance: _i(m['walletBalance']),
        sufficient: m['sufficient'] == true,
      );
}

/// Ариза (Firestore `insurance_requests` ёки агент рўйхати — бир хил майдонлар).
class InsuranceRequest {
  const InsuranceRequest({
    required this.id,
    required this.status,
    required this.policyType,
    required this.vehicleType,
    required this.termMonths,
    required this.price,
    this.uid = '',
    this.carPlate = '',
    this.carModel = '',
    this.carBrand = '',
    this.carYear = 0,
    this.walletPaid = 0,
    this.oilDiscount = 0,
    this.incentiveApplied = 0,
    this.policyNumber = '',
    this.validFrom = '',
    this.validTo = '',
    this.cancelReason = '',
    this.regionId = '',
    this.zone = '',
    this.zoneDerived = '',
    this.zoneSource = '',
    this.driverScope = '',
    this.techFront = false,
    this.techBack = false,
    this.techPurged = false,
    this.createdAt,
  });
  final String id;
  final String status;
  final String policyType;
  final String vehicleType;
  final int termMonths;
  final int price;
  final String uid;
  final String carPlate;
  final String carModel;
  final String carBrand;
  final int carYear;
  final int walletPaid;
  final int oilDiscount;
  final int incentiveApplied;
  final String policyNumber;
  final String validFrom;
  final String validTo;
  final String cancelReason;
  final String regionId;
  final String zone;
  final String zoneDerived;

  /// 'user' — мижоз ҳудудни ўзи танлаган (агент полисда текширади).
  final String zoneSource;
  final String driverScope;

  /// Техпаспорт расмлари юкланганми (сервер белгиси; эга 2026-11-28). purged — 30 кундан кейин ўчирилган.
  final bool techFront;
  final bool techBack;
  final bool techPurged;
  bool get techComplete => techFront && techBack;
  final DateTime? createdAt;

  factory InsuranceRequest.fromMap(String id, Map m) {
    final car = m['car'] is Map ? m['car'] as Map : const {};
    final pol = m['policy'] is Map ? m['policy'] as Map : const {};
    DateTime? created;
    final c = m['createdAt'] ?? m['createdAtMs'];
    if (c is num) created = DateTime.fromMillisecondsSinceEpoch(c.toInt());
    try {
      if (c != null && c is! num) created = (c as dynamic).toDate() as DateTime;
    } catch (_) {}
    return InsuranceRequest(
      id: id,
      status: _s(m['status']),
      policyType: _s(m['policyType']),
      vehicleType: _s(m['vehicleType']),
      termMonths: _i(m['termMonths']),
      price: _i(m['price']),
      uid: _s(m['uid']),
      carPlate: _s(car['plate']),
      carModel: _s(car['model']),
      carBrand: _s(car['brand']),
      carYear: _i(car['year']),
      walletPaid: _i(m['walletPaid']),
      oilDiscount: _i(m['oilDiscount']),
      incentiveApplied: _i(m['incentiveApplied']),
      policyNumber: _s(pol['number']),
      validFrom: _s(pol['validFrom']),
      validTo: _s(pol['validTo']),
      cancelReason: _s(m['cancelReason']),
      regionId: _s(m['regionId']),
      zone: _s(m['zone']),
      zoneDerived: _s(m['zoneDerived']),
      zoneSource: _s(m['zoneSource']),
      driverScope: _s(m['driverScope']),
      techFront: m['techPassport'] is Map && (m['techPassport'] as Map)['front'] == true,
      techBack: m['techPassport'] is Map && (m['techPassport'] as Map)['back'] == true,
      techPurged: m['techPassport'] is Map && (m['techPassport'] as Map)['purged'] == true,
      createdAt: created,
    );
  }
}

/// Сервер хатосидан фойдаланувчи матни (3 тил, сервер `messages`) ва ички код.
({String code, String? message}) insuranceErrorOf(Object e, String lang) {
  if (e is FirebaseFunctionsException) {
    final d = e.details;
    if (d is Map) {
      final msgs = d['messages'];
      final text = msgs is Map ? msgs[lang] ?? msgs['uz_Cyrl'] : null;
      return (code: '${d['code'] ?? e.code}', message: text == null ? null : '$text');
    }
    return (code: e.code, message: null);
  }
  return (code: 'UNKNOWN', message: null);
}

class CarInsuranceService {
  CarInsuranceService({FirebaseFunctions? functions}) : _functions = functions;
  final FirebaseFunctions? _functions;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  Future<Map> _call(String name, [Map<String, dynamic> data = const {}]) async {
    final res = await _fns.httpsCallable(name).call<Object?>(data);
    final d = res.data;
    return d is Map ? d : const {};
  }

  Future<InsuranceState> myState() async => InsuranceState.fromMap(await _call('insuranceGetMyState'));

  Future<({String requestId, int price})> createRequest({
    required String policyType,
    required String vehicleType,
    required int termMonths,
    required String idempotencyKey,
    String zone = '',
    String driverScope = '',
  }) async {
    final d = await _call('insuranceCreateRequest', {
      'policyType': policyType,
      'vehicleType': vehicleType,
      'termMonths': termMonths,
      'idempotencyKey': idempotencyKey,
      if (zone.isNotEmpty) 'zone': zone,
      if (driverScope.isNotEmpty) 'driverScope': driverScope,
    });
    return (requestId: _s(d['requestId']), price: _i(d['price']));
  }

  /// Техпаспорт расми (эга 2026-11-28): side 'front' | 'back'; сервер текширади (JPG/PNG/WebP ≤ 5 МБ).
  Future<void> uploadTechPassport(String requestId, String side, String fileBase64) =>
      _call('insuranceUploadTechPassport', {'requestId': requestId, 'side': side, 'fileBase64': fileBase64});

  /// Техпаспорт ҳаволалари (эгаси ёки агент): {front, back} — бўш бўлса йўқ.
  Future<({String front, String back})> techPassportLinks(String requestId) async {
    final d = await _call('insuranceGetTechPassportLinks', {'requestId': requestId});
    return (front: _s(d['front']), back: _s(d['back']));
  }

  /// Агент тузатиши: тўланган аризада нарх ўзгарса сервер PRICE_CHANGED_CANCEL_REQUIRED (бекор қилиш керак).
  Future<int> agentCorrect({
    required String requestId,
    required String zone,
    required String vehicleType,
    required String driverScope,
    required String reason,
  }) async =>
      _i((await _call('insuranceAgentCorrect', {
        'requestId': requestId,
        'zone': zone,
        'vehicleType': vehicleType,
        'driverScope': driverScope,
        'reason': reason,
      }))['price']);

  Future<InsuranceQuote> quote(String requestId) async =>
      InsuranceQuote.fromMap(await _call('insuranceQuote', {'requestId': requestId}));

  Future<void> pay(String requestId) => _call('insurancePayRequest', {'requestId': requestId});

  Future<void> cancelMine(String requestId) => _call('insuranceCancelMyRequest', {'requestId': requestId});

  Future<void> setExpiry({required String expiresOn, required String policyType}) =>
      _call('insuranceSetMyExpiry', {'expiresOn': expiresOn, 'policyType': policyType});

  Future<void> chooseCarOffer(String option) => _call('insuranceChooseCarOffer', {'option': option});

  Future<String> policyLink(String requestId) async =>
      _s((await _call('insuranceGetPolicyLink', {'requestId': requestId}))['url']);

  // ── Агент / сервис маркази / админ ──
  Future<List<InsuranceRequest>> agentList(String status) async {
    final d = await _call('insuranceAgentListRequests', {'status': status});
    return [
      for (final r in (d['requests'] is List ? d['requests'] as List : const []))
        if (r is Map) InsuranceRequest.fromMap(_s(r['requestId']), r),
    ];
  }

  Future<void> agentStart(String requestId) => _call('insuranceAgentStart', {'requestId': requestId});

  Future<void> agentIssue({
    required String requestId,
    required String policyNumber,
    required String validFrom,
    required String validTo,
    required String fileBase64,
  }) =>
      _call('insuranceAgentIssuePolicy', {
        'requestId': requestId,
        'policyNumber': policyNumber,
        'validFrom': validFrom,
        'validTo': validTo,
        'fileBase64': fileBase64,
      });

  Future<void> agentCancel(String requestId, String reason) =>
      _call('insuranceAgentCancel', {'requestId': requestId, 'reason': reason});

  Future<Map> submitServiceReport({required String centerId, required String date, required List<String> plates}) =>
      _call('insuranceSubmitServiceReport', {'centerId': centerId, 'date': date, 'plates': plates});

  Future<List<Map>> listServiceReports() async {
    final d = await _call('insuranceListServiceReports', {'limit': 50});
    return [for (final r in (d['reports'] is List ? d['reports'] as List : const [])) if (r is Map) r];
  }

  Future<Map> adminSettings() => _call('adminInsuranceGetSettings');
  Future<void> adminSaveConfig(Map<String, dynamic> config) => _call('adminInsuranceSaveConfig', {'config': config});
  Future<int> adminPublishTariff(List<Map<String, dynamic>> rows, String note) async =>
      _i((await _call('adminInsurancePublishTariff', {'rows': rows, 'note': note}))['version']);
  Future<void> adminSaveCampaign(int year, Map<String, dynamic> campaign) =>
      _call('adminInsuranceSaveCampaign', {'year': year, 'campaign': campaign});
}

// ── Соф ёрдамчилар (тест учун) ──

/// 'YYYY-MM-DD' → 'DD.MM.YYYY'.
String insuranceDisplayDate(String key) {
  final p = key.split('-');
  return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : key;
}

/// DateTime → 'YYYY-MM-DD'.
String insuranceDateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Тугашига қолган кун (бугун = 0; ўтиб кетган — манфий); сана йўқ — null.
int? insuranceDaysLeft(String expiresOn, DateTime today) {
  final p = expiresOn.split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime.utc(y, m, d).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
}

/// Мой дастури жараёни: «1/2 мой алмаштириш — 50% чегирма тайёр» учун параметрлар; дастур йўқ — null.
({int n, int goal, int pct})? insuranceOilProgress(InsuranceEnrollment? e) {
  if (e == null || e.option != 'oil' || e.oilGoal <= 0) return null;
  return (n: e.oilChanges.clamp(0, e.oilGoal), goal: e.oilGoal, pct: e.discountUsed ? 0 : e.discountPct);
}

/// Мавжуд танловлардан турлар (тартибли, такрорсиз).
List<String> insuranceDistinct(Iterable<String> xs) {
  final out = <String>[];
  for (final x in xs) {
    if (!out.contains(x)) out.add(x);
  }
  return out;
}

/// schema 2 нархини олдиндан кўриш (сервер барибир қайта ҳисоблайди); мос қатор йўқ — `null`.
InsuranceOption? insuranceZoneOption(
  Iterable<InsuranceOption> options, {
  required String policyType,
  required String zone,
  required String vehicleType,
  required String driverScope,
  required int termMonths,
}) {
  for (final o in options) {
    if (o.policyType == policyType &&
        o.zone == zone &&
        o.vehicleType == vehicleType &&
        o.driverScope == driverScope &&
        o.termMonths == termMonths) {
      return o;
    }
  }
  return null;
}

/// Ҳудуддаги тоифалар (МДҲ — фақат енгил ва юк; сервер `CIS_VEHICLE_TYPES`), жадвалдаги тартибда.
List<String> insuranceVehiclesFor(Iterable<InsuranceOption> options, String policyType, String zone) =>
    insuranceDistinct(options.where((o) => o.policyType == policyType && o.zone == zone).map((o) => o.vehicleType));