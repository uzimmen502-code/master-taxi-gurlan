import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/factories/data/factories_repository.dart';
import 'package:ava_gurlan/features/factories/domain/factory_profile.dart';
import 'package:ava_gurlan/features/factories/screens/factories_screen.dart';
import 'package:ava_gurlan/features/factories/screens/factory_manage_screen.dart';
import 'package:ava_gurlan/features/factories/screens/factory_page_screen.dart';
import 'package:ava_gurlan/features/vacancies/domain/job_vacancy.dart';
import 'package:ava_gurlan/models/job_ad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// «Işlab çiqaruvçi zavod/fabrikalar» (ega 2026-11-28). Delegatsiz `context.tr(key)` kalitning özini qaytaradi.

const _owner = '998901110001';
const _visitor = '998901110002';

Business _biz(String id, {
  BusinessCategory category = BusinessCategory.manufacturing,
  String status = 'active',
  Map<String, Object?>? factory,
  String producer = '',
  DateTime? createdAt,
}) =>
    Business.tryFromMap(id, {
      'ownerId': _owner,
      'name': 'Завод $id',
      'category': category.wire,
      'phone': _owner,
      'lat': 41.5,
      'lng': 60.5,
      'status': status,
      'description': 'Пахта толаси',
      if (factory != null) 'factory': factory,
      if (producer.isNotEmpty) 'producerVerification': {'status': producer},
      if (createdAt != null) 'createdAt': createdAt,
    })!;

JobAd _vac(String id) => JobAd(
      id: id,
      type: 'work',
      text: 'Талаб',
      title: 'Ишчи',
      authorName: '',
      authorPhone: _owner,
      address: '',
      isUrgent: false,
      status: 'active',
      vacancy: JobVacancy.tryParse({'position': 'Ишчи', 'requirements': 'Талаб 10 белги', 'salaryNegotiable': true}),
    );

Widget _app(Widget child) => MaterialApp(home: child);

void main() {
  group('Model (sof)', () {
    test('FactoryOptions.fromMap / ProducerStatus — buzuq qiymat öçiq', () {
      expect(FactoryOptions.fromMap(null), FactoryOptions.none);
      expect(FactoryOptions.fromMap({'showVideos': 'yes'}).showVideos, isFalse);
      final o = FactoryOptions.fromMap({'sellWholesale': true, 'publishVacancies': true});
      expect(o.toCallable(), {'sellWholesale': true, 'showVideos': false, 'publishVacancies': true, 'avaSupplierReady': false});
      expect(ProducerStatus.fromMap({'status': 'approved'}), ProducerStatus.approved);
      expect(ProducerStatus.fromMap({'status': 'weird'}), ProducerStatus.none);
    });

    test('Business: factory/producerVerification öqiladi; toCallable da YÖQ (client yoza olmaydi)', () {
      final b = _biz('a', factory: {'showVideos': true}, producer: 'approved');
      expect(b.factoryOptions.showVideos, isTrue);
      expect(b.producerStatus, 'approved');
      expect(b.toCallable().keys.any((k) => k.contains('factory') || k.contains('producer')), isFalse);
      expect(showsVerifiedProducerBadge(b), isTrue);
      expect(showsVerifiedProducerBadge(_biz('r', category: BusinessCategory.retail, producer: 'approved')), isFalse);
      expect(showsVerifiedProducerBadge(_biz('x', status: 'blocked', producer: 'approved')), isFalse);
    });

    test('mergeFactoryRings: tartib, takrorsiz, bloklangan/zavod emas çiqadi, tasdiqlangan oldinda, limit', () {
      final d1 = _biz('d1', createdAt: DateTime(2026, 1, 2));
      final d2 = _biz('d2', producer: 'approved', createdAt: DateTime(2026, 1, 1));
      final r1 = _biz('r1');
      final out = mergeFactoryRings([
        [d1, d2, _biz('blk', status: 'blocked')],
        [r1, d1, _biz('shop', category: BusinessCategory.retail)],
        [_biz('n1'), r1],
      ], limit: 4);
      expect(out.map((b) => b.id), ['d2', 'd1', 'r1', 'n1']);
    });
  });

  group('Ekranlar', () {
    testWidgets('FactoriesScreen: röyxat + tasdiq belgisi', (t) async {
      await t.pumpWidget(_app(FactoriesScreen(load: () async => [_biz('a', producer: 'approved'), _biz('b')])));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('factory_card_a')), findsOneWidget);
      expect(find.byKey(const ValueKey('factory_verified_a')), findsOneWidget);
      expect(find.byKey(const ValueKey('factory_verified_b')), findsNothing);
    });

    testWidgets('FactoriesScreen: böş — factory_empty', (t) async {
      await t.pumpWidget(_app(FactoriesScreen(load: () async => const [])));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('factory_empty')), findsOneWidget);
    });

    testWidgets('FactoryPageScreen: zavod yoqmagan bloklar (video/vakansiya) körinmaydi; mehmonga boşqariş yöq', (t) async {
      var vacLoads = 0;
      await t.pumpWidget(_app(FactoryPageScreen(
        business: _biz('a'),
        myUid: _visitor,
        loadProducts: (_) async => const [],
        loadClips: (_) async => const [],
        loadVacancies: (_) async {
          vacLoads++;
          return [_vac('v1')];
        },
        loadSeller: (_) async => null,
      )));
      await t.pumpAndSettle();
      expect(find.text('factory_vacancies'), findsNothing);
      expect(vacLoads, 0, reason: 'öçiq blok uçun sörov ham yuborilmaydi');
      expect(find.byKey(const ValueKey('factory_manage')), findsNothing);
      expect(find.byKey(const ValueKey('factory_verified_badge')), findsNothing);
      expect(find.byKey(const ValueKey('factory_write')), findsOneWidget);
    });

    testWidgets('FactoryPageScreen: vakansiyalar yoqilgan + tasdiqlangan; egaga boşqariş', (t) async {
      await t.pumpWidget(_app(FactoryPageScreen(
        business: _biz('a', factory: {'publishVacancies': true}, producer: 'approved'),
        myUid: _owner,
        loadProducts: (_) async => const [],
        loadVacancies: (_) async => [_vac('v1')],
        loadSeller: (_) async => null,
      )));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('factory_verified_badge')), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const ValueKey('vac_card_v1')), 200);
      expect(find.byKey(const ValueKey('vac_card_v1')), findsOneWidget);
      expect(find.byKey(const ValueKey('factory_manage')), findsOneWidget);
      expect(find.byKey(const ValueKey('factory_write')), findsNothing);
    });

    testWidgets('FactoryManageScreen: tanlov serverga, tasdiq söraş; natija pop qilinadi', (t) async {
      final calls = <(FactoryOptions, bool)>[];
      Business? popped;
      await t.pumpWidget(_app(Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async {
              popped = await Navigator.of(ctx).push<Business>(MaterialPageRoute(
                builder: (_) => FactoryManageScreen(
                  business: _biz('a'),
                  save: (o, req) async {
                    calls.add((o, req));
                    return req ? ProducerStatus.pending : '';
                  },
                ),
              ));
            },
            child: const Text('open'),
          ),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('factory_verify_status_none'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('factory_opt_supplier')));
      await t.pump();
      await t.ensureVisible(find.byKey(const ValueKey('factory_request_verify')));
      await t.tap(find.byKey(const ValueKey('factory_request_verify')));
      await t.pumpAndSettle();
      expect(calls.single.$1.avaSupplierReady, isTrue);
      expect(calls.single.$2, isTrue);
      expect(popped?.producerStatus, ProducerStatus.pending);
      expect(popped?.factoryOptions.avaSupplierReady, isTrue);
    });
  });
}
