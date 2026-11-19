import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

/// Excel (.xlsx) орқали оммавий юклаш (эга, 2026-11-19) — сервер callable'лари
/// (`functions/wholesale_import.js`, default codebase, us-central1). Клиент фақат файлни
/// юборади ва натижани кўрсатади: текширув, нарх, ҳолат — ҳаммаси серверда (CLAUDE.md 18/44).
class WholesaleImportService {
  WholesaleImportService({FirebaseFunctions? functions}) : _fn = functions;

  final FirebaseFunctions? _fn;
  FirebaseFunctions get _functions => _fn ?? FirebaseFunctions.instance;

  /// Сервер чегараси билан бир хил (`LIMITS.maxFileBytes`): катта файл юборилмайди.
  static const maxFileBytes = 5 * 1024 * 1024;

  Future<({String fileName, Uint8List bytes})> template(String market) async {
    final r = await _functions
        .httpsCallable('wholesaleImportTemplate')
        .call<Map<String, dynamic>>({'market': market});
    final d = Map<String, dynamic>.from(r.data);
    return (
      fileName: (d['fileName'] as String?) ?? 'ava_products.xlsx',
      bytes: base64Decode((d['base64'] as String?) ?? ''),
    );
  }

  /// Янги сўров ID (бир файл = бир ID; қайта уриниш шу ID билан — квота иккинчи марта санамайди).
  static String newRequestId() {
    final r = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return 'wi-${List.generate(20, (_) => chars[r.nextInt(chars.length)]).join()}';
  }

  Future<WholesaleImportPreview> preview({
    required String market,
    required String fileName,
    required Uint8List bytes,
    required String requestId,
  }) async {
    final r = await _functions
        .httpsCallable('wholesaleImportPreview',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 130)))
        .call<Map<String, dynamic>>({
      'market': market,
      'fileName': fileName,
      'fileBase64': base64Encode(bytes),
      'clientRequestId': requestId,
    });
    return WholesaleImportPreview.fromMap(Map<String, dynamic>.from(r.data));
  }

  Future<WholesaleImportResult> confirm(String batchId) async {
    final r = await _functions
        .httpsCallable('wholesaleImportConfirm',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 545)))
        .call<Map<String, dynamic>>({'batchId': batchId});
    return WholesaleImportResult.fromMap(Map<String, dynamic>.from(r.data));
  }
}

int _int(Object? v) => v is num ? v.toInt() : 0;
List<String> _strs(Object? v) =>
    v is List ? v.map((e) => '$e').toList(growable: false) : const [];

/// Битта қатор (Excel'даги қатор рақами билан).
class WholesaleImportRow {
  const WholesaleImportRow({
    required this.row,
    required this.sku,
    required this.title,
    required this.status,
    this.price,
    this.errors = const [],
  });

  final int row;
  final String sku;
  final String title;

  /// Preview: `create` | `update` | `unchanged` | `error`.
  /// Confirm: `created` | `updated` | `unchanged` | `error` | `pending`.
  final String status;
  final int? price;
  final List<String> errors;

  bool get isError => status == 'error' || errors.isNotEmpty;

  factory WholesaleImportRow.fromMap(Map<String, dynamic> m) => WholesaleImportRow(
        row: _int(m['row']),
        sku: (m['sku'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        status: (m['action'] as String?) ?? (m['status'] as String?) ?? '',
        price: m['price'] is num ? (m['price'] as num).toInt() : null,
        errors: _strs(m['errors']),
      );
}

List<WholesaleImportRow> _rows(Object? v) => v is List
    ? v
        .whereType<Map>()
        .map((m) => WholesaleImportRow.fromMap(Map<String, dynamic>.from(m)))
        .toList(growable: false)
    : const [];

class WholesaleImportPreview {
  const WholesaleImportPreview({
    required this.batchId,
    required this.total,
    required this.ready,
    required this.errors,
    required this.create,
    required this.update,
    required this.unchanged,
    required this.rows,
    required this.quotaUsed,
    required this.quotaMax,
  });

  final String batchId;
  final int total;
  final int ready;
  final int errors;
  final int create;
  final int update;
  final int unchanged;
  final List<WholesaleImportRow> rows;
  final int quotaUsed;
  final int quotaMax;

  /// Ёзиладигани бор (янги ёки ўзгарган) — «Тасдиқлаш» тугмаси.
  bool get canConfirm => create + update > 0;

  List<WholesaleImportRow> get errorRows => rows.where((r) => r.isError).toList(growable: false);

  factory WholesaleImportPreview.fromMap(Map<String, dynamic> d) {
    final c = Map<String, dynamic>.from((d['counts'] as Map?) ?? const {});
    final q = Map<String, dynamic>.from((d['quota'] as Map?) ?? const {});
    return WholesaleImportPreview(
      batchId: (d['batchId'] as String?) ?? '',
      total: _int(c['total']),
      ready: _int(c['ready']),
      errors: _int(c['errors']),
      create: _int(c['create']),
      update: _int(c['update']),
      unchanged: _int(c['unchanged']),
      rows: _rows(d['rows']),
      quotaUsed: _int(q['used']),
      quotaMax: _int(q['max']),
    );
  }
}

class WholesaleImportResult {
  const WholesaleImportResult({
    required this.batchId,
    required this.status,
    required this.created,
    required this.updated,
    required this.unchanged,
    required this.failed,
    required this.pending,
    required this.autoApprove,
    required this.rows,
  });

  final String batchId;

  /// `done` | `partial` (вақт тугади — «Давом эттириш» қолганини ёзади).
  final String status;
  final int created;
  final int updated;
  final int unchanged;
  final int failed;
  final int pending;
  final bool autoApprove;
  final List<WholesaleImportRow> rows;

  bool get isPartial => status == 'partial';
  List<WholesaleImportRow> get errorRows => rows.where((r) => r.isError).toList(growable: false);

  factory WholesaleImportResult.fromMap(Map<String, dynamic> d) {
    final c = Map<String, dynamic>.from((d['counts'] as Map?) ?? const {});
    return WholesaleImportResult(
      batchId: (d['batchId'] as String?) ?? '',
      status: (d['status'] as String?) ?? '',
      created: _int(c['created']),
      updated: _int(c['updated']),
      unchanged: _int(c['unchanged']),
      failed: _int(c['error']),
      pending: _int(c['pending']),
      autoApprove: d['autoApprove'] == true,
      rows: _rows(d['rows']),
    );
  }
}

/// Сервер диагностика коди → фойдаланувчи матни калити (3 тилда, `assets/lang/*.json`).
/// Номаълум код — умумий матн (стек/ички код кўрсатилмайди, CLAUDE.md 25).
const kWholesaleImportErrorCodes = <String>{
  'SKU_REQUIRED', 'SKU_TOO_LONG', 'SKU_DUPLICATE', 'SKU_HAS_PACKS', 'TITLE_INVALID', 'DESC_INVALID',
  'PRICE_REQUIRED', 'PRICE_NOT_INT', 'PRICE_INVALID', 'CURRENCY_INVALID', 'UNIT_TOO_LONG', 'MOQ_INVALID',
  'WEIGHT_INVALID', 'DIMS_INVALID', 'DIMS_NEED_WEIGHT', 'DELIVERY_DAYS_INVALID', 'IMAGE_REQUIRED',
  'IMAGE_URL_INVALID', 'IMAGE_FETCH_FAILED', 'IMAGE_BLOCKED_HOST', 'IMAGE_TOO_LARGE', 'IMAGE_NOT_IMAGE',
  'IMAGE_TIMEOUT', 'WRITE_FAILED',
  // Файл/сўров даражаси
  'FILE_EMPTY', 'FILE_TOO_LARGE', 'FILE_NOT_XLSX', 'HEADER_MISSING', 'NO_ROWS', 'TOO_MANY_ROWS',
  'DAILY_LIMIT', 'SELLER_NOT_APPROVED', 'SHIP_FROM_REQUIRED', 'BATCH_EXPIRED', 'BATCH_BUSY',
};

String wholesaleImportErrorKey(String code) => kWholesaleImportErrorCodes.contains(code)
    ? 'wsimp_err_${code.toLowerCase()}'
    : 'wsimp_err_generic';

/// [FirebaseFunctionsException] дан диагностика коди (`details.code`), бўлмаса ''.
String wholesaleImportExceptionCode(Object e) {
  if (e is FirebaseFunctionsException) {
    final d = e.details;
    if (d is Map && d['code'] is String) return d['code'] as String;
  }
  return '';
}
