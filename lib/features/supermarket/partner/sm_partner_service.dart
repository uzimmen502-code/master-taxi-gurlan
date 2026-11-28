import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

import '../../admin_web/services/admin_supermarket_service.dart' show SmImportPreview, SmImportResult;
import '../domain/sm_units.dart' show kSmUnits;

/// «AVA Супермаркет» ҳамкори (эга 2026-11-28, а-вариант): тасдиқланган Улгуржи сотувчиси ўз таклифларини супермаркетга
/// чиқаради. Ҳаммаси серверда (`supermarket.js` partner* callable'лари): эгалик, модерация, нарх бутун сўм.
/// Харидор «AVA Супермаркет»ни кўради; ҳамкорга тўлов КЕЙИНГА қолдирилган.

int _i(Object? v) => v is num ? v.toInt() : 0;
String _s(Object? v) => v == null ? '' : '$v';

class SmPartnerOffer {
  const SmPartnerOffer({
    required this.productId,
    required this.sku,
    required this.name,
    required this.price,
    required this.groupId,
    this.stock,
    this.varietyNames = const {},
    this.qualityNames = const {},
    this.packLabel = '',
    this.unit = '',
    this.qtyStep,
    this.weighed = false,
    this.partnerStatus = 'active',
    this.moderation = 'pending',
    this.moderationReason = '',
    this.varietyId = '',
  });

  final String productId;
  final String sku;
  final String name;
  final int price;
  final String groupId;
  final num? stock;
  final String varietyId;
  final Map<String, String> varietyNames;
  final Map<String, String> qualityNames;
  final String packLabel;
  final String unit;
  final num? qtyStep;
  final bool weighed;

  /// Ҳамкор танлаган ҳолат (active | out_of_stock | hidden).
  final String partnerStatus;

  /// pending | approved | rejected — харидорга фақат approved кўринади.
  final String moderation;
  final String moderationReason;

  static Map<String, String> _names(Object? v) => {
        if (v is Map)
          for (final e in v.entries)
            if (e.value is String) '${e.key}': e.value as String,
      };

  factory SmPartnerOffer.fromMap(Map m) {
    final v = m['smVariety'] is Map ? m['smVariety'] as Map : const {};
    return SmPartnerOffer(
      productId: _s(m['productId']),
      sku: _s(m['sku']),
      name: _s(m['name']),
      price: _i(m['price']),
      groupId: _s(m['smGroupId']),
      stock: m['stock'] is num ? m['stock'] as num : null,
      varietyId: _s(v['id']),
      varietyNames: _names(v['names']),
      qualityNames: _names(m['smQuality']),
      packLabel: _s(m['packLabel']),
      unit: _s(m['unit']),
      qtyStep: m['qtyStep'] is num ? m['qtyStep'] as num : null,
      weighed: m['weighed'] == true,
      partnerStatus: _s(m['smPartnerStatus']).isEmpty ? 'active' : _s(m['smPartnerStatus']),
      moderation: _s(m['smModeration']).isEmpty ? 'pending' : _s(m['smModeration']),
      moderationReason: _s(m['smModerationReason']),
    );
  }
}

/// Шакл маълумоти → сервер `offer` (соф; тест учун). Хатолар — lang калитлари.
({Map<String, dynamic> offer, List<String> problems}) smPartnerOfferFromForm({
  required String sku,
  required String groupId,
  required String varietyId,
  required Map<String, String> varietyNames,
  required Map<String, String> qualityNames,
  required String packLabel,
  required String price,
  required String stock,
  required String status,
  String unit = '',
}) {
  final p = int.tryParse(price.replaceAll(RegExp(r'[\s ]'), ''));
  final st = num.tryParse(stock.trim().replaceAll(',', '.'));
  final quality = {for (final e in qualityNames.entries) if (e.value.trim().isNotEmpty) e.key: e.value.trim()};
  final problems = [
    if (!RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(sku.trim())) 'smp_err_sku',
    if (groupId.isEmpty) 'smp_err_group',
    if (!RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(varietyId.trim())) 'smp_err_variety_id',
    for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru'])
      if ((varietyNames[l] ?? '').trim().isEmpty) 'smp_err_variety_name',
    if (quality.isNotEmpty && quality.length != 3) 'smp_err_quality',
    if (p == null || p <= 0) 'smp_err_price',
    if (st == null || st < 0) 'smp_err_stock',
    // Бирлик ихтиёрий: бўш — гуруҳники (сервер offer.unit || group.unit); фақат kSmUnits (сервер ҳам текширади).
    if (unit.trim().isNotEmpty && !kSmUnits.contains(unit.trim())) 'smp_err_unit',
  ];
  return (
    offer: {
      'smGroupId': groupId,
      'smVariety': {
        'id': varietyId.trim(),
        'names': {for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru']) l: (varietyNames[l] ?? '').trim()},
      },
      if (quality.length == 3) 'smQuality': quality,
      if (packLabel.trim().isNotEmpty) 'packLabel': packLabel.trim(),
      if (kSmUnits.contains(unit.trim())) 'unit': unit.trim(),
      'price': p ?? 0,
      'stock': st ?? 0,
      'smStatus': const ['active', 'out_of_stock', 'hidden'].contains(status) ? status : 'active',
    },
    problems: problems.toSet().toList(),
  );
}

class SmPartnerService {
  SmPartnerService({FirebaseFunctions? functions}) : _functions = functions;
  final FirebaseFunctions? _functions;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  Future<Map> _call(String name, Map<String, dynamic> data, {Duration? timeout}) async {
    final res = await _fns
        .httpsCallable(name, options: timeout == null ? null : HttpsCallableOptions(timeout: timeout))
        .call<Object?>(data);
    return res.data is Map ? res.data as Map : const {};
  }

  Future<List<SmPartnerOffer>> myOffers() async {
    final d = await _call('partnerListSupermarketOffers', const {});
    return [
      for (final o in (d['offers'] is List ? d['offers'] as List : const []))
        if (o is Map) SmPartnerOffer.fromMap(o),
    ];
  }

  Future<String> upsert(String sku, Map<String, dynamic> offer) async =>
      _s((await _call('partnerUpsertSupermarketOffer', {'sku': sku, 'offer': offer}))['productId']);

  Future<({String fileName, Uint8List bytes})> importTemplate() async {
    final d = await _call('partnerSupermarketImportTemplate', const {});
    return (fileName: _s(d['fileName']).isEmpty ? 'ava_supermarket_partner.xlsx' : _s(d['fileName']), bytes: base64Decode(_s(d['base64'])));
  }

  Future<SmImportPreview> importPreview({required String fileName, required Uint8List bytes, required String clientRequestId}) async =>
      SmImportPreview.fromMap(Map<String, dynamic>.from(await _call(
        'partnerSupermarketImportPreview',
        {'fileName': fileName, 'fileBase64': base64Encode(bytes), 'clientRequestId': clientRequestId},
        timeout: const Duration(seconds: 130),
      )));

  Future<SmImportResult> importConfirm(String batchId) async => SmImportResult.fromMap(Map<String, dynamic>.from(
      await _call('partnerSupermarketImportConfirm', {'batchId': batchId}, timeout: const Duration(seconds: 545))));
}
