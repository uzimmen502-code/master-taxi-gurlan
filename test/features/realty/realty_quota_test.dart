import 'package:ava_gurlan/features/realty/widgets/realty_quota_strip.dart';
import 'package:ava_gurlan/repositories/realty_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _known = RealtyQuota(used: 1, limit: 2, isPro: false);
const _full = RealtyQuota(used: 2, limit: 2, isPro: false);

Future<void> _pump(
  WidgetTester t, {
  required bool loaded,
  required RealtyQuota quota,
  bool busy = false,
  VoidCallback? onOpen,
}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RealtyQuotaStrip(loaded: loaded, quota: quota, busy: busy, onOpenPackage: onOpen ?? () {}),
    ),
  ));
}

void main() {
  group('RealtyQuota', () {
    test('REGRESSION: маълумот йўқ (limit 0) «тўлди» ЭМАС', () {
      expect(RealtyQuota.empty.isKnown, isFalse);
      expect(RealtyQuota.empty.isFull, isFalse);
    });

    test('маълум квота: тўлди / тўлмади', () {
      expect(_known.isKnown, isTrue);
      expect(_known.isFull, isFalse);
      expect(_known.left, 1);
      expect(_full.isFull, isTrue);
      expect(_full.left, 0);
    });

    test('лимитдан ошган (used > limit) ҳам тўлди', () {
      expect(const RealtyQuota(used: 3, limit: 2, isPro: false).isFull, isTrue);
    });
  });

  group('RealtyQuotaStrip', () {
    testWidgets('REGRESSION: квота юкланмади (тармоқ) — «Пакетни кўриш» ва «тўлди» ЙЎҚ', (t) async {
      await _pump(t, loaded: true, quota: RealtyQuota.empty);
      expect(find.byKey(const ValueKey('realty-open-package')), findsNothing);
    });

    testWidgets('ҳали юкланмаган — тугма йўқ', (t) async {
      await _pump(t, loaded: false, quota: _full);
      expect(find.byKey(const ValueKey('realty-open-package')), findsNothing);
    });

    testWidgets('бўш ўрин бор — тугма йўқ', (t) async {
      await _pump(t, loaded: true, quota: _known);
      expect(find.byKey(const ValueKey('realty-open-package')), findsNothing);
    });

    testWidgets('ўрин тугади — тугма бор ва БИР босишда пакет очилади (диалогсиз)', (t) async {
      var opened = 0;
      await _pump(t, loaded: true, quota: _full, onOpen: () => opened++);
      await t.tap(find.byKey(const ValueKey('realty-open-package')));
      await t.pump();
      expect(opened, 1);
      expect(find.byType(AlertDialog), findsNothing, reason: 'тугма тагидаги матн огоҳлантиришнинг ўзи — иккинчи диалог керак эмас');
    });

    testWidgets('юбориш давом этаётганда тугма ўчиқ', (t) async {
      var opened = 0;
      await _pump(t, loaded: true, quota: _full, busy: true, onOpen: () => opened++);
      await t.tap(find.byKey(const ValueKey('realty-open-package')), warnIfMissed: false);
      await t.pump();
      expect(opened, 0);
    });
  });
}
