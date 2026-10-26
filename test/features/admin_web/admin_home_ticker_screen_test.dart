import 'package:ava_gurlan/features/admin_web/screens/admin_home_ticker_screen.dart';
import 'package:ava_gurlan/models/home_ticker_ad.dart';
import 'package:ava_gurlan/repositories/home_ticker_repository.dart';
import 'package:ava_gurlan/services/admin_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Админ «Бегущая строка»: бош экран баннери ишлатмайдиган созламалар (давомийлик, анимация, шрифт, тезлик)
/// админда йўқ, сақлаганда эса мавжуд қийматлар ўзгармайди (эга, 2026-10-26). Firebase'сиз.
class _NoDb implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('Firebase ишлатилмайди');
}

class _FakeAdmin extends AdminService {
  _FakeAdmin() : super(db: _NoDb());

  @override
  Future<bool> isCurrentUserAdmin() async => true;
}

class _FakeRepo extends HomeTickerRepository {
  _FakeRepo(this.items) : super(db: _NoDb());

  final List<HomeTickerAd> items;
  final updated = <HomeTickerAd>[];

  @override
  Stream<List<HomeTickerAd>> watchForAdmin({int limit = 100}) => Stream.value(items);

  @override
  Future<void> update(HomeTickerAd ad) async => updated.add(ad);
}

HomeTickerAd _ad() => HomeTickerAd(
      id: 'a1', text: 'Такси керакми? Илова орқали чақиринг.', audience: 'all', durationSec: 6, scrollSpeed: 45,
      animationStyle: 'typewriter', fontSize: 13, priority: 0, active: true,
    );

Future<_FakeRepo> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(1400, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final repo = _FakeRepo([_ad()]);
  await t.pumpWidget(MultiProvider(
    providers: [
      Provider<AdminService>.value(value: _FakeAdmin()),
      Provider<HomeTickerRepository>.value(value: repo),
    ],
    child: const MaterialApp(home: AdminHomeTickerScreen()),
  ));
  await t.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('рўйхат: «Давомийлик»/«Анимация» тугмалари ва давомийлик/шрифт/тезлик чиплари йўқ', (t) async {
    await _pump(t);
    expect(find.text('Такси керакми? Илова орқали чақиринг.'), findsOneWidget);
    expect(find.text('Янги матн'), findsOneWidget);
    expect(find.text('Давомийлик'), findsNothing);
    expect(find.text('Анимация'), findsNothing);
    expect(find.textContaining('Давомийлик:'), findsNothing);
    expect(find.textContaining('Шрифт:'), findsNothing);
    expect(find.textContaining('Тезлик:'), findsNothing);
    expect(find.text('Устуворлик: 0'), findsOneWidget, reason: 'ишлайдиган майдонлар қолади');
  });

  testWidgets('таҳрир: анимация/шрифт/давомийлик/тезлик майдони йўқ, изоҳ бор; сақлаганда эски қийматлар ўзгармайди', (t) async {
    final repo = await _pump(t);
    await t.tap(find.text('Таҳрир'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ticker_fixed_behaviour_note')), findsOneWidget);
    expect(find.text('Анимация услуби'), findsNothing);
    expect(find.text('Шрифт ўлчами'), findsNothing);
    expect(find.text('Давомийлик (бир матн)'), findsNothing);
    expect(find.textContaining('тезлиги'), findsNothing);
    expect(find.text('Устуворлик'), findsOneWidget);

    await t.tap(find.text('Сақлаш'));
    await t.pumpAndSettle();
    expect(repo.updated, hasLength(1));
    final saved = repo.updated.single;
    expect(saved.durationSec, 6);
    expect(saved.animationStyle, 'typewriter');
    expect(saved.fontSize, 13);
    expect(saved.scrollSpeed, 45);
    expect(saved.text, 'Такси керакми? Илова орқали чақиринг.');
  });
}
