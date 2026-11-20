// Админ — «AVA Супермаркет» (1-босқич, эга 2026-11-20).
//
// Сервер (functions/supermarket.js, feat/supermarket-srv 48a7d45f) — ҳаммаси admin/superadmin callable,
// версия + `admin_audit` серверда:
//   • `adminSetSupermarketTaxonomy({taxonomy:{categories}, expectedVersion})`;
//   • `adminSetSupermarketSettings({settings, expectedVersion, reason})` — `settings/supermarket` (админ ўқийди);
//   • `adminUpsertSupermarketOffer({productId, offer, cost?})` — `platform_products` (sm майдонлари ва нарх
//     фақат CF орқали; янги таклиф `active:false` — эски Улгуржи/«Тавсия» лентасига тушмайди);
//   • `adminSettleSupermarketWeights({orderId, lines:[{productId, actualQty}]})`;
//   • `adminRemoveSupermarketLine({orderId, productId, reason})`.
// Харид нархи — `platform_products/{id}/private/cost` (фақат админ ўқийди).

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../supermarket/domain/sm_offer.dart';
import '../../supermarket/domain/sm_qty.dart';
import '../../supermarket/domain/sm_taxonomy.dart';

export 'admin_business_orders_service.dart' show parseTesterPhones, invalidTesterPhones;

/// Сервер `STAGES` (42-банд).
const kSmStages = <String>['off', 'internal', 'pilot', 'public'];

/// Сервер `ID_RE` (гуруҳ/нав id).
final kSmIdRe = RegExp(r'^[a-z][a-z0-9_]{1,39}$');

/// Сервер `DISTRICT_RE`.
final kSmDistrictRe = RegExp(r'^[a-z0-9_-]{2,40}$');

const _langs = ['uz_Cyrl', 'uz_Latn', 'ru'];

bool _allLangs(Map<String, String> m) => _langs.every((l) => (m[l] ?? '').trim().isNotEmpty);

/// `settings/supermarket`: `{stage, testerIds[], districtIds[], slots[{id, names, startMin, endMin}],
/// cutoffMin (0..720 — бугунги слот бошланишидан неча дақиқа олдин қабул тўхтайди), weighHoldPercent (0..50)}`.
class SmSettings {
  const SmSettings({
    this.stage = 'off',
    this.testerIds = const [],
    this.districtIds = const [],
    this.slots = const [],
    this.cutoffMin = 0,
    this.weighHoldPercent = 10,
    this.version = 0,
  });

  final String stage;
  final List<String> testerIds;
  final List<String> districtIds;
  final List<SmSlotDraft> slots;
  final int cutoffMin;
  final int weighHoldPercent;

  /// Ҳужжат версияси (`expectedVersion` учун; ҳужжат йўқ — 0).
  final int version;

  factory SmSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const SmSettings();
    List<String> list(Object? v) => v is List ? v.map((e) => '$e').where((e) => e.isNotEmpty).toList() : const [];
    final stage = '${m['stage'] ?? ''}';
    return SmSettings(
      stage: kSmStages.contains(stage) ? stage : 'off',
      testerIds: list(m['testerIds']),
      districtIds: list(m['districtIds']),
      slots: [
        if (m['slots'] is List) ...(m['slots'] as List).map(SmSlotDraft.fromMap).whereType<SmSlotDraft>(),
      ],
      cutoffMin: (m['cutoffMin'] as num?)?.toInt() ?? 0,
      weighHoldPercent: (m['weighHoldPercent'] as num?)?.toInt() ?? 10,
      version: (m['version'] as num?)?.toInt() ?? 0,
    );
  }

  /// Сервер `SETTINGS_KEYS` — фақат шулар (номаълум калит рад этилади).
  Map<String, dynamic> toMap() => {
        'stage': stage,
        'testerIds': testerIds,
        'districtIds': districtIds,
        'slots': [for (final s in slots) s.toMap()],
        'cutoffMin': cutoffMin,
        'weighHoldPercent': weighHoldPercent,
      };

  /// Сервер валидатори кўзгуси (Кирилл матн).
  List<String> problems() => [
        if (!kSmStages.contains(stage)) 'Босқич нотўғри',
        if (testerIds.length > 200) 'Синовчилар 200 тадан кўп',
        if (districtIds.length > 50) 'Туманлар 50 тадан кўп',
        for (final d in districtIds)
          if (!kSmDistrictRe.hasMatch(d)) 'Туман ID нотўғри: $d',
        if (slots.length > 12) 'Вақтлар 12 тадан кўп',
        if (cutoffMin < 0 || cutoffMin > 720) 'Қабул тўхташи 0..720 дақиқа',
        if (weighHoldPercent < 0 || weighHoldPercent > 50) 'Тортиш ушлаши 0..50%',
      ];
}

class SmSlotDraft {
  const SmSlotDraft({required this.id, required this.startMin, required this.endMin, this.names = const {}});

  final String id;
  final int startMin;
  final int endMin;
  final Map<String, String> names;

  static SmSlotDraft? fromMap(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    return SmSlotDraft(
      id: raw['id'] as String,
      startMin: (raw['startMin'] as num?)?.toInt() ?? 0,
      endMin: (raw['endMin'] as num?)?.toInt() ?? 0,
      names: smNames(raw['names']),
    );
  }

  /// Сервер 3 тилда ном талаб қилади — йўқ бўлса «10:00–12:00» (ҳамма тилда бир хил).
  Map<String, dynamic> toMap() {
    final label = '${hhmm(startMin)}–${hhmm(endMin)}';
    return {
      'id': id,
      'names': {for (final l in _langs) l: (names[l] ?? '').trim().isNotEmpty ? names[l] : label},
      'startMin': startMin,
      'endMin': endMin,
    };
  }
}

String hhmm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// «10:00-12:00» қаторларидан слотлар; хато қатор — [errors]га. id = `s1000_1200` (сервер `SLOT_ID_RE`).
({List<SmSlotDraft> slots, List<String> errors}) parseSlotLines(String raw) {
  final slots = <SmSlotDraft>[];
  final errors = <String>[];
  final re = RegExp(r'^(\d{1,2}):(\d{2})\s*[-–]\s*(\d{1,2}):(\d{2})$');
  for (final line in raw.split('\n')) {
    final s = line.trim();
    if (s.isEmpty) continue;
    final m = re.firstMatch(s);
    if (m == null) {
      errors.add(s);
      continue;
    }
    final a = int.parse(m[1]!) * 60 + int.parse(m[2]!);
    final b = int.parse(m[3]!) * 60 + int.parse(m[4]!);
    if (int.parse(m[2]!) > 59 || int.parse(m[4]!) > 59 || a >= b || a > 1439 || b > 24 * 60) {
      errors.add(s);
      continue;
    }
    final id = 's${m[1]!.padLeft(2, '0')}${m[2]}_${m[3]!.padLeft(2, '0')}${m[4]}';
    if (slots.any((x) => x.id == id)) continue;
    slots.add(SmSlotDraft(id: id, startMin: a, endMin: b));
  }
  slots.sort((x, y) => x.startMin.compareTo(y.startMin));
  return (slots: slots, errors: errors);
}

String slotLines(List<SmSlotDraft> slots) => slots.map((s) => '${hhmm(s.startMin)}-${hhmm(s.endMin)}').join('\n');

/// Таклиф формаси → `adminUpsertSupermarketOffer.offer` (сервер `OFFER_KEYS`).
class SmOfferDraft {
  SmOfferDraft({
    required this.groupId,
    required this.varietyId,
    required this.varietyNames,
    required this.qualityNames,
    required this.packLabel,
    required this.unit,
    required this.qtyStep,
    required this.weighed,
    required this.stock,
    required this.status,
    required this.price,
    this.name = '',
    this.packQty,
    this.packUnit = '',
  });

  /// Қадоқ ичидаги миқдор (масалан 0.9) ва бирлиги (kg|l|piece) — «1 л — N сўм» учун (эга 2026-11-20).
  /// Иккаласи бирга ёки ҳеч бири.
  final num? packQty;
  final String packUnit;

  final String groupId;
  final String varietyId;
  final Map<String, String> varietyNames;
  final Map<String, String> qualityNames;
  final String packLabel;
  final String unit;
  final num qtyStep;
  final bool weighed;
  final num? stock;
  final String status;
  final int price;

  /// Бўш — сервер «гуруҳ + нав» дан ясайди.
  final String name;

  /// Сервер `validateOffer` кўзгуси (Кирилл матн).
  List<String> validate(SmTaxonomy taxonomy) => [
        if (taxonomy.group(groupId) == null) 'Гуруҳ таксономияда йўқ',
        if (!kSmIdRe.hasMatch(varietyId)) 'Нав ID: кичик лотин ҳарф билан бошланади (a-z, 0-9, _), 2–40 белги',
        if (!_allLangs(varietyNames)) 'Нав номи 3 тилда бўлиши шарт',
        if (qualityNames.isNotEmpty && !_allLangs(qualityNames)) 'Сифат — ё 3 тилда, ё бўш',
        if (packLabel.length > 40) 'Қадоқ ёрлиғи 40 белгигача',
        if (!kSmUnits.contains(unit)) 'Бирлик нотўғри',
        if (qtyStep <= 0 || smToMilli(qtyStep) <= 0 || smToMilli(qtyStep) > 1000000) 'Қадам 0 дан катта бўлсин',
        if (price <= 0) 'Нарх бутун сон, 0 дан катта',
        if (stock == null) 'Қолдиқни киритинг (0 — тугаган)',
        if (stock != null && stock! < 0) 'Қолдиқ манфий бўлмасин',
        if (!['active', 'out_of_stock', 'hidden'].contains(status)) 'Ҳолат нотўғри',
        if (packQty != null && (packQty! <= 0 || smToMilli(packQty!) <= 0)) 'Қадоқ миқдори 0 дан катта бўлсин',
        if (packQty != null && !kSmPackUnits.contains(packUnit)) 'Қадоқ бирлиги: кг, л ёки дона',
        if (packQty == null && packUnit.isNotEmpty) 'Қадоқ миқдорини киритинг (ёки бирликни бўш қолдиринг)',
      ];

  Map<String, dynamic> toOffer() => {
        'smGroupId': groupId,
        'smVariety': {'id': varietyId, 'names': varietyNames},
        if (qualityNames.isNotEmpty) 'smQuality': qualityNames,
        'packLabel': packLabel,
        'unit': unit,
        'qtyStep': qtyStep,
        'weighed': weighed,
        'stock': stock,
        'smStatus': status,
        'price': price,
        if (name.trim().isNotEmpty) 'name': name.trim(),
        if (packQty != null) 'packQty': packQty,
        if (packQty != null) 'packUnit': packUnit,
      };
}

class AdminSupermarketException implements Exception {
  const AdminSupermarketException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Сервер хатоси → админга Кирилл матн (`details.messages.uz_Cyrl` + валидатор `errors`).
String smAdminErrorText(String name, String grpcCode, Object? details) {
  if (details is Map) {
    final msg = details['messages'] is Map ? '${(details['messages'] as Map)['uz_Cyrl'] ?? ''}' : '';
    final errs = details['errors'] is List ? (details['errors'] as List).take(5).join('; ') : '';
    final code = '${details['code'] ?? grpcCode}';
    final head = msg.isNotEmpty ? msg : 'Сервер рад этди';
    return '$head ($code)${errs.isEmpty ? '' : ': $errs'}';
  }
  return 'Сервер рад этди ($name): $grpcCode';
}

/// Админ маълумот манбаи (тестда алмаштирилади).
class AdminSupermarketService {
  AdminSupermarketService({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _dbOverride = db,
        _fnsOverride = functions;

  final FirebaseFirestore? _dbOverride;
  final FirebaseFunctions? _fnsOverride;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  FirebaseFunctions get _fns => _fnsOverride ?? FirebaseFunctions.instance;

  Future<Map<String, dynamic>?> loadTaxonomyRaw() async =>
      (await _db.collection('taxonomy').doc('supermarket').get()).data();

  /// Сервер фақат `categories` калитини қабул қилади.
  Future<void> saveTaxonomy(List<dynamic> categories, int expectedVersion) => _call('adminSetSupermarketTaxonomy', {
        'taxonomy': {'categories': categories},
        'expectedVersion': expectedVersion,
      });

  Future<List<SmOffer>> loadOffers(SmTaxonomy tx) async {
    final snap = await _db.collection('platform_products').where('smGroupId', isGreaterThan: '').limit(2000).get();
    return [for (final d in snap.docs) SmOffer.fromMap(d.id, d.data(), group: tx.group('${d.data()['smGroupId']}'))];
  }

  /// Янги таклиф ID (клиентда ясалади — қайта юбориш идемпотент; сервер `PRODUCT_ID_RE` 6–64).
  String newProductId() => _db.collection('platform_products').doc().id;

  Future<Map<String, dynamic>?> loadCost(String productId) async =>
      (await _db.collection('platform_products').doc(productId).collection('private').doc('cost').get()).data();

  Future<void> saveOffer({
    required String productId,
    required SmOfferDraft draft,
    int? purchasePrice,
    String? supplier,
  }) =>
      _call('adminUpsertSupermarketOffer', {
        'productId': productId,
        'offer': draft.toOffer(),
        if (purchasePrice != null) 'cost': {'purchasePrice': purchasePrice, 'supplier': supplier ?? ''},
      });

  Future<SmSettings> loadSettings() async =>
      SmSettings.fromMap((await _db.collection('settings').doc('supermarket').get()).data());

  Future<void> saveSettings(SmSettings s, {required int expectedVersion, required String reason}) =>
      _call('adminSetSupermarketSettings', {'settings': s.toMap(), 'expectedVersion': expectedVersion, 'reason': reason});

  /// Супермаркет буюртмалари: `type == 'platform'` ВА `subtype == 'supermarket'` (иккита тенглик —
  /// бир майдонли индекслар бирлашади); тартиб клиентда (композит индекс шарт эмас).
  Stream<List<Map<String, dynamic>>> watchOrders({int limit = 100}) => _db
      .collection('orders')
      .where('type', isEqualTo: 'platform')
      .where('subtype', isEqualTo: 'supermarket')
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) {'id': d.id, ...d.data()}]..sort((a, b) => _ts(b).compareTo(_ts(a))));

  static int _ts(Map<String, dynamic> m) {
    final v = m['createdAt'];
    return v is Timestamp ? v.millisecondsSinceEpoch : 0;
  }

  Future<void> settleWeights(String orderId, List<({String productId, num actualQty})> lines) =>
      _call('adminSettleSupermarketWeights', {
        'orderId': orderId,
        'lines': [for (final l in lines) {'productId': l.productId, 'actualQty': l.actualQty}],
      });

  Future<void> removeLine(String orderId, String productId, String reason) =>
      _call('adminRemoveSupermarketLine', {'orderId': orderId, 'productId': productId, 'reason': reason});

  /// Етишмовчилик (2-босқич шартномаси): `adminReportSupermarketShortage({orderId, productId, availableQty,
  /// substitutes:[offerId]})` — admin/dispatcher; мижоз ўзи танлайди (respondSupermarketShortage).
  Future<void> reportShortage(String orderId, String productId, num availableQty, List<String> substitutes) =>
      _call('adminReportSupermarketShortage', {
        'orderId': orderId,
        'productId': productId,
        'availableQty': availableQty,
        'substitutes': substitutes,
      });

  /// Excel импорт (2-босқич; Улгуржи импорт оқими кўзгуси). Жавоб шакли — wholesale_import билан бир хил деб
  /// олинди (`{fileName, base64}` / `{batchId, counts, rows}` / `{status, counts, rows}`) — сервер тасдиқлаши керак.
  Future<({String fileName, Uint8List bytes})> importTemplate() async {
    final d = await _callData('adminSupermarketImportTemplate', const {});
    return (
      fileName: (d['fileName'] as String?) ?? 'ava_supermarket.xlsx',
      bytes: base64Decode((d['base64'] as String?) ?? ''),
    );
  }

  Future<SmImportPreview> importPreview({required String fileName, required Uint8List bytes, required String clientRequestId}) async =>
      SmImportPreview.fromMap(await _callData(
        'adminSupermarketImportPreview',
        {'fileName': fileName, 'fileBase64': base64Encode(bytes), 'clientRequestId': clientRequestId},
        timeout: const Duration(seconds: 130),
      ));

  Future<SmImportResult> importConfirm(String batchId) async => SmImportResult.fromMap(await _callData(
        'adminSupermarketImportConfirm',
        {'batchId': batchId},
        timeout: const Duration(seconds: 545),
      ));

  Future<void> _call(String name, Map<String, dynamic> data) => _callData(name, data);

  Future<Map<String, dynamic>> _callData(String name, Map<String, dynamic> data, {Duration? timeout}) async {
    try {
      final r = await _fns
          .httpsCallable(name, options: timeout == null ? null : HttpsCallableOptions(timeout: timeout))
          .call<Object?>(data);
      return r.data is Map ? Map<String, dynamic>.from(r.data as Map) : const {};
    } on FirebaseFunctionsException catch (e) {
      throw AdminSupermarketException(smAdminErrorText(name, e.code, e.details));
    }
  }
}

/// Сервер чегараси (Улгуржи импорт билан бир хил деб олинди — UNKNOWN, сервер тасдиқлайди).
const kSmImportMaxBytes = 5 * 1024 * 1024;

int _i(Object? v) => v is num ? v.toInt() : 0;

/// Импорт қатори: Excel қатор рақами, калит (`productId`|`sku`|`id`), ном, амал/ҳолат, хатолар.
class SmImportRow {
  const SmImportRow({required this.row, required this.key, required this.title, required this.status, this.errors = const []});

  final int row;
  final String key;
  final String title;
  final String status;
  final List<String> errors;

  bool get isError => status == 'error' || errors.isNotEmpty;

  factory SmImportRow.fromMap(Map m) => SmImportRow(
        row: _i(m['row']),
        key: '${m['productId'] ?? m['sku'] ?? m['id'] ?? ''}',
        title: '${m['title'] ?? m['name'] ?? ''}',
        status: '${m['action'] ?? m['status'] ?? ''}',
        errors: m['errors'] is List ? [for (final e in m['errors'] as List) '$e'] : const [],
      );
}

List<SmImportRow> _rows(Object? v) => v is List ? [for (final m in v) if (m is Map) SmImportRow.fromMap(m)] : const [];

class SmImportPreview {
  const SmImportPreview({
    required this.batchId,
    required this.total,
    required this.errors,
    required this.create,
    required this.update,
    required this.unchanged,
    required this.rows,
  });

  final String batchId;
  final int total;
  final int errors;
  final int create;
  final int update;
  final int unchanged;
  final List<SmImportRow> rows;

  bool get canConfirm => batchId.isNotEmpty && create + update > 0;
  List<SmImportRow> get errorRows => rows.where((r) => r.isError).toList();

  factory SmImportPreview.fromMap(Map<String, dynamic> d) {
    final c = d['counts'] is Map ? d['counts'] as Map : const {};
    return SmImportPreview(
      batchId: '${d['batchId'] ?? ''}',
      total: _i(c['total']),
      errors: _i(c['errors'] ?? c['error']),
      create: _i(c['create']),
      update: _i(c['update']),
      unchanged: _i(c['unchanged']),
      rows: _rows(d['rows']),
    );
  }
}

class SmImportResult {
  const SmImportResult({
    required this.status,
    required this.created,
    required this.updated,
    required this.unchanged,
    required this.failed,
    required this.rows,
  });

  /// `done` | `partial` (вақт тугади — «Давом эттириш» ўша batchId билан).
  final String status;
  final int created;
  final int updated;
  final int unchanged;
  final int failed;
  final List<SmImportRow> rows;

  bool get isPartial => status == 'partial';
  List<SmImportRow> get errorRows => rows.where((r) => r.isError).toList();

  factory SmImportResult.fromMap(Map<String, dynamic> d) {
    final c = d['counts'] is Map ? d['counts'] as Map : const {};
    return SmImportResult(
      status: '${d['status'] ?? ''}',
      created: _i(c['created']),
      updated: _i(c['updated']),
      unchanged: _i(c['unchanged']),
      failed: _i(c['error'] ?? c['errors']),
      rows: _rows(d['rows']),
    );
  }
}

/// Етишмовчилик формаси текшируви (Кирилл матн; бўш — тўғри). Сервер ҳам текширади.
List<String> smShortageAdminProblems({required num orderedQty, required num? availableQty, required List<String> substitutes}) => [
      if (availableQty == null || availableQty < 0) 'Мавжуд миқдор — 0 ёки мусбат сон',
      if (availableQty != null && availableQty >= orderedQty) 'Мавжуд миқдор буюртмадагидан кам бўлиши керак',
      if (substitutes.length > 3) 'Ўрнини босувчи — кўпи билан 3 та',
      if (substitutes.toSet().length != substitutes.length) 'Ўрнини босувчи такрорланмасин',
    ];
