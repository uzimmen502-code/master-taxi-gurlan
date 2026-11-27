// «AVA Супермаркет» ҳамкор модели (эга 2026-11-28): намуна сотилмайди, ҳамкор шакли ва экрани.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ava_gurlan/features/admin_web/services/admin_supermarket_service.dart' show SmImportPreview, SmImportResult;
import 'package:ava_gurlan/features/supermarket/domain/sm_offer.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_taxonomy.dart';
import 'package:ava_gurlan/features/supermarket/partner/sm_partner_screen.dart';
import 'package:ava_gurlan/features/supermarket/partner/sm_partner_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../restaurants/restaurants_l10n_harness.dart';

Map<String, String> _n(String s) => {'uz_Cyrl': s, 'uz_Latn': s, 'ru': s};

final _tx = SmTaxonomy.fromMap({
  'version': 1,
  'categories': [
    {
      'id': 'vegetables', 'order': 1, 'icon': 'vegetables', 'names': _n('Сабзавот'),
      'groups': [
        {'id': 'potato', 'order': 1, 'names': _n('Картошка'), 'unit': 'kg', 'step': 0.5, 'weighed': true, 'synonyms': []},
      ],
    },
  ],
});

class _FakePartner extends SmPartnerService {
  List<SmPartnerOffer> offers = [];
  final upserts = <(String, Map<String, dynamic>)>[];
  final previews = <String>[];
  final confirms = <String>[];

  @override
  Future<List<SmPartnerOffer>> myOffers() async => offers;

  @override
  Future<String> upsert(String sku, Map<String, dynamic> offer) async {
    upserts.add((sku, offer));
    offers = [
      SmPartnerOffer.fromMap({'productId': 'ps_k_$sku', 'sku': sku, 'name': 'Картошка Қизил', 'price': offer['price'], 'smGroupId': 'potato', 'stock': 10, 'smModeration': 'pending'}),
    ];
    return 'ps_k_$sku';
  }

  @override
  Future<SmImportPreview> importPreview({required String fileName, required Uint8List bytes, required String clientRequestId}) async {
    previews.add(fileName);
    return SmImportPreview.fromMap({
      'batchId': 'smi_x',
      'counts': {'total': 2, 'ready': 1, 'errors': 1, 'create': 1, 'update': 0},
      'rows': [
        {'row': 3, 'sku': 'bad', 'action': 'error', 'errors': ['SKU_NOT_OWNED']},
      ],
    });
  }

  @override
  Future<SmImportResult> importConfirm(String batchId) async {
    confirms.add(batchId);
    return SmImportResult.fromMap({'status': 'done', 'counts': {'created': 1, 'updated': 0, 'error': 1}});
  }
}

void main() {
  test('намуна: харидорга кўринади (visible), лекин сотилмайди (available false), ёрлиқ «Намуна»', () {
    final o = SmOffer.fromMap('pp_1', {'smGroupId': 'potato', 'smStatus': 'active', 'price': 5000, 'stock': 10, 'smSample': true}, group: _tx.group('potato'));
    expect([o.sample, o.visible, o.available], [true, true, false]);
    expect(smUnavailableKey(o), 'sm_sample_badge');
    final p = SmOffer.fromMap('ps_1', {'smGroupId': 'potato', 'smStatus': 'active', 'price': 5000, 'stock': 10}, group: _tx.group('potato'));
    expect([p.sample, p.available, smUnavailableKey(p)], [false, true, 'sm_out_of_stock']);
  });

  test('ҳамкор шакли: тўғри → сервер offer; хатолар калит билан', () {
    final ok = smPartnerOfferFromForm(
      sku: 'kart-1', groupId: 'potato', varietyId: 'red', varietyNames: _n('Қизил'), qualityNames: const {},
      packLabel: '', price: '6 000', stock: '12,5', status: 'active',
    );
    expect(ok.problems, isEmpty);
    expect(ok.offer, {
      'smGroupId': 'potato', 'smVariety': {'id': 'red', 'names': _n('Қизил')}, 'price': 6000, 'stock': 12.5, 'smStatus': 'active',
    });
    final bad = smPartnerOfferFromForm(
      sku: 'a b', groupId: '', varietyId: 'Red!', varietyNames: const {'uz_Cyrl': 'x'}, qualityNames: const {'ru': 'x'},
      packLabel: '', price: '0', stock: '-1', status: 'zzz',
    );
    expect(bad.problems.toSet(), {'smp_err_sku', 'smp_err_group', 'smp_err_variety_id', 'smp_err_variety_name', 'smp_err_quality', 'smp_err_price', 'smp_err_stock'});
  });

  testWidgets('экран: маҳсулот қўшиш → upsert, рўйхатда «Текширувда»; Excel: preview → confirm', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final d = JsonL10nDelegate();
    final svc = _FakePartner();
    await t.pumpWidget(l10nApp(
      delegate: d,
      home: SmPartnerScreen(
        service: svc,
        loadTaxonomy: () async => _tx,
        pickFile: () async => (name: 'p.xlsx', bytes: Uint8List.fromList([1, 2, 3])),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('smp_empty')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('smp_add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('smp_f_sku')), 'kart-1');
    await t.tap(find.byKey(const ValueKey('smp_f_group')));
    await t.pumpAndSettle();
    await t.tap(find.text('Картошка').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('smp_f_variety_id')), 'red');
    for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru']) {
      await t.enterText(find.byKey(ValueKey('smp_f_variety_$l')), 'Қизил');
    }
    await t.enterText(find.byKey(const ValueKey('smp_f_price')), '6000');
    await t.enterText(find.byKey(const ValueKey('smp_f_stock')), '10');
    await t.tap(find.byKey(const ValueKey('smp_f_save')));
    await t.pumpAndSettle();
    expect(svc.upserts.single.$1, 'kart-1');
    expect(svc.upserts.single.$2['price'], 6000);
    expect(find.byKey(const ValueKey('smp_offer_kart-1')), findsOneWidget);
    expect(find.textContaining(d.tr('smp_mod_pending')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('smp_pick')));
    await t.pumpAndSettle();
    expect(svc.previews, ['p.xlsx']);
    expect(find.textContaining('SKU_NOT_OWNED'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('smp_confirm')));
    await t.pumpAndSettle();
    expect(svc.confirms, ['smi_x']);
    expect(find.byKey(const ValueKey('smp_result')), findsOneWidget);
  });

  test('smp_* ва sm_sample_badge калитлари 3 тилда; uz_Latn янги алифбода', () {
    Map<String, dynamic> j(String l) => jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;
    final c = j('uz_Cyrl').keys.where((k) => k.startsWith('smp_') || k == 'sm_sample_badge').toSet();
    expect(c.length, greaterThanOrEqualTo(40));
    expect(j('uz_Latn').keys.where((k) => k.startsWith('smp_') || k == 'sm_sample_badge').toSet(), c);
    expect(j('ru').keys.where((k) => k.startsWith('smp_') || k == 'sm_sample_badge').toSet(), c);
    final latn = j('uz_Latn');
    for (final k in c) {
      expect(RegExp(r"o'|g'|sh|ch", caseSensitive: false).hasMatch('${latn[k]}'), isFalse, reason: k);
    }
  });
}
