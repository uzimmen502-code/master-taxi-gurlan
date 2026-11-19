import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ava_gurlan/features/admin_web/screens/wholesale_moderation_screen.dart'
    show wholesaleImportBatches;
import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/screens/wholesale_import_screen.dart';
import 'package:ava_gurlan/features/wholesale/services/wholesale_import_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Excel юклаш (эга, 2026-11-19): жавоб моделлари, хато матнлари (3 тил), экран оқими.
/// Тестда `tr` калитнинг ўзини қайтаради.
class _FakeService extends WholesaleImportService {
  _FakeService({this.previewError});

  final Object? previewError;
  int previews = 0;
  int confirms = 0;
  String? lastRequestId;
  Map<String, dynamic> confirmResponse = {
    'batchId': 'wsi_x',
    'status': 'done',
    'autoApprove': false,
    'counts': {'total': 3, 'created': 1, 'updated': 1, 'unchanged': 0, 'error': 1, 'pending': 0},
    'rows': [
      {'row': 4, 'sku': 'C-3', 'title': 'Шакар', 'status': 'error', 'errors': ['IMAGE_FETCH_FAILED']},
    ],
  };

  @override
  Future<WholesaleImportPreview> preview({
    required String market,
    required String fileName,
    required Uint8List bytes,
    required String requestId,
  }) async {
    previews++;
    lastRequestId = requestId;
    if (previewError != null) throw previewError!;
    return WholesaleImportPreview.fromMap(_previewMap);
  }

  @override
  Future<WholesaleImportResult> confirm(String batchId) async {
    confirms++;
    return WholesaleImportResult.fromMap(confirmResponse);
  }
}

const _previewMap = <String, dynamic>{
  'batchId': 'wsi_x',
  'counts': {'total': 3, 'ready': 2, 'errors': 1, 'create': 1, 'update': 1, 'unchanged': 0},
  'rows': [
    {'row': 2, 'sku': 'A-1', 'title': 'Ун', 'price': 350000, 'action': 'create', 'errors': []},
    {'row': 3, 'sku': 'B-2', 'title': 'Гуруч', 'price': 20000, 'action': 'update', 'errors': []},
    {'row': 4, 'sku': 'C-3', 'title': 'Шакар', 'price': null, 'action': 'error', 'errors': ['PRICE_INVALID', 'SKU_DUPLICATE']},
  ],
  'quota': {'used': 3, 'max': 10},
};

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  group('моделлар', () {
    test('preview: сонлар, хато қаторлари, тасдиқлаш мумкинми', () {
      final p = WholesaleImportPreview.fromMap(_previewMap);
      expect(p.batchId, 'wsi_x');
      expect((p.ready, p.errors, p.create, p.update), (2, 1, 1, 1));
      expect(p.canConfirm, isTrue);
      expect(p.errorRows.single.row, 4);
      expect(p.errorRows.single.errors, ['PRICE_INVALID', 'SKU_DUPLICATE']);
      expect(p.rows.first.price, 350000);
      final none = WholesaleImportPreview.fromMap({
        'counts': {'ready': 3, 'unchanged': 3},
      });
      expect(none.canConfirm, isFalse, reason: 'ҳаммаси ўзгармаган — юклаш тугмаси ўчиқ');
    });

    test('confirm: partial / done', () {
      final r = WholesaleImportResult.fromMap({
        'status': 'partial',
        'counts': {'created': 2, 'pending': 5},
      });
      expect(r.isPartial, isTrue);
      expect(r.pending, 5);
      expect(WholesaleImportResult.fromMap(const {}).isPartial, isFalse);
    });

    test('модел sku/importBatchId ни ўқийди; админ фильтри юклашларни санайди', () {
      final a = WholesaleProduct.fromMap('imp_1', {'title': 'Ун', 'sku': ' A-1 ', 'importBatchId': 'wsi_aaa'});
      final b = WholesaleProduct.fromMap('imp_2', {'title': 'Гуруч', 'sku': 'B', 'importBatchId': 'wsi_aaa'});
      final c = WholesaleProduct.fromMap('x', {'title': 'Қўлда'});
      expect(a.sku, 'A-1');
      expect(c.sku, isEmpty);
      expect(c.importBatchId, isEmpty);
      expect(wholesaleImportBatches([a, b, c]), {'wsi_aaa': 2});
    });

    test('сўров ID сервер шаклига мос (8..64, [A-Za-z0-9_-])', () {
      final a = WholesaleImportService.newRequestId();
      expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(a), isTrue);
      expect(a, isNot(WholesaleImportService.newRequestId()));
    });

    test('хато коди → калит; номаълум → умумий; деталлардан код', () {
      expect(wholesaleImportErrorKey('PRICE_INVALID'), 'wsimp_err_price_invalid');
      expect(wholesaleImportErrorKey('SOMETHING_NEW'), 'wsimp_err_generic');
      expect(wholesaleImportErrorKey(''), 'wsimp_err_generic');
      expect(
        wholesaleImportExceptionCode(FirebaseFunctionsException(
            code: 'resource-exhausted', message: 'x', details: {'code': 'DAILY_LIMIT'})),
        'DAILY_LIMIT',
      );
      expect(wholesaleImportExceptionCode(Exception('x')), '');
    });

    test('ҳар бир хато коди ва экран калити 3 тилда бор (uz_Cyrl, uz_Latn, ru)', () {
      final keys = <String>{
        for (final c in kWholesaleImportErrorCodes) wholesaleImportErrorKey(c),
        'wsimp_err_generic', 'wsimp_title', 'wsimp_entry', 'wsimp_entry_sub', 'wsimp_confirm_btn',
        'wsimp_row_n', 'wsimp_quota', 'wholesale_field_unit_price', 'wholesale_extra_tiers',
        'wholesale_extra_tiers_remove', 'wholesale_shipping_group',
      };
      for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
        final m = jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
        for (final k in keys) {
          expect((m[k] as String?)?.trim().isNotEmpty, isTrue, reason: '$lang: $k');
        }
      }
    });
  });

  group('экран', () {
    testWidgets('бошланғич: 2 қадам (шаблон, файл)', (tester) async {
      await tester.pumpWidget(_host(WholesaleImportScreen(market: 'wholesale', service: _FakeService())));
      expect(find.byKey(const ValueKey('wsimp-template')), findsOneWidget);
      expect(find.byKey(const ValueKey('wsimp-pick')), findsOneWidget);
      expect(find.text('wholesale_title'), findsOneWidget);
    });

    testWidgets('файл → текширув → хатолар қатор рақами билан → тасдиқ → натижа', (tester) async {
      final svc = _FakeService();
      await tester.pumpWidget(_host(WholesaleImportScreen(
        market: 'china',
        service: svc,
        pickFile: () async => (name: 'a.xlsx', bytes: Uint8List.fromList([1, 2, 3])),
      )));
      expect(find.text('wholesale_title_china'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wsimp-pick')));
      await tester.pumpAndSettle();
      expect(svc.previews, 1);
      expect(find.text('wsimp_count_ready: 2'), findsOneWidget);
      expect(find.text('wsimp_count_errors: 1'), findsOneWidget);
      expect(find.textContaining('wsimp_row_n'), findsOneWidget);
      expect(find.textContaining('wsimp_err_price_invalid · wsimp_err_sku_duplicate'), findsOneWidget);
      expect(find.text('wsimp_update_note'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wsimp-confirm')));
      await tester.pumpAndSettle();
      expect(svc.confirms, 1);
      expect(find.text('wsimp_result_done'), findsOneWidget);
      expect(find.text('wsimp_count_created: 1'), findsOneWidget);
      expect(find.textContaining('wsimp_err_image_fetch_failed'), findsOneWidget);
      expect(find.byKey(const ValueKey('wsimp-done')), findsOneWidget);
    });

    testWidgets('partial → «Давом эттириш» яна confirm чақиради', (tester) async {
      final svc = _FakeService()
        ..confirmResponse = {
          'batchId': 'wsi_x',
          'status': 'partial',
          'counts': {'created': 1, 'pending': 2},
          'rows': [],
        };
      await tester.pumpWidget(_host(WholesaleImportScreen(
        market: 'wholesale',
        service: svc,
        pickFile: () async => (name: 'a.xlsx', bytes: Uint8List.fromList([1])),
      )));
      await tester.tap(find.byKey(const ValueKey('wsimp-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wsimp-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('wsimp_result_partial'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wsimp-continue')));
      await tester.pumpAndSettle();
      expect(svc.confirms, 2);
    });

    testWidgets('сервер хатоси (кунлик чегара) — дўстона матн, ички код кўрсатилмайди', (tester) async {
      final svc = _FakeService(
        previewError: FirebaseFunctionsException(
            code: 'resource-exhausted', message: 'DAILY_LIMIT internal', details: {'code': 'DAILY_LIMIT'}),
      );
      await tester.pumpWidget(_host(WholesaleImportScreen(
        market: 'wholesale',
        service: svc,
        pickFile: () async => (name: 'a.xlsx', bytes: Uint8List.fromList([1])),
      )));
      await tester.tap(find.byKey(const ValueKey('wsimp-pick')));
      await tester.pumpAndSettle();
      expect(find.text('wsimp_err_daily_limit'), findsOneWidget);
      expect(find.textContaining('internal'), findsNothing);
    });

    testWidgets('5 МБ дан катта файл серверга юборилмайди', (tester) async {
      final svc = _FakeService();
      await tester.pumpWidget(_host(WholesaleImportScreen(
        market: 'wholesale',
        service: svc,
        pickFile: () async =>
            (name: 'big.xlsx', bytes: Uint8List(WholesaleImportService.maxFileBytes + 1)),
      )));
      await tester.tap(find.byKey(const ValueKey('wsimp-pick')));
      await tester.pumpAndSettle();
      expect(svc.previews, 0);
      expect(find.text('wsimp_err_file_too_large'), findsOneWidget);
    });
  });
}
