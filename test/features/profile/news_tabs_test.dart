// «Хабарлар» → «Буюртма» (эга, 2026-10-19): (1) экран «милтиллаб» қолмасин —
// рўйхат қайта чизилганда оқим қайта очилмайди; (2) ўқилмаган карта жирний
// (қалин), ўқилгани оддий шрифт билан ажралади (белги/фон йўқ, эга 2026-10-19); (3) хабарни ЎЧИРИШ тугмаси: сервердаги users/{uid}/dismissed_news га ёзади — барча қурилмада йўқолади (эга 2026-10-20).
// Матнлар `context.tr` орқали — тестда делегат йўқ, шунинг учун калит кўринади.

import 'dart:async';

import 'package:ava_gurlan/features/profile/screens/general_news_tab.dart';
import 'package:ava_gurlan/features/profile/screens/order_news_tab.dart';
import 'package:ava_gurlan/models/news_item.dart';
import 'package:ava_gurlan/models/news_read_state.dart';
import 'package:ava_gurlan/repositories/news_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo implements NewsRepository {
  _Repo(this.items);

  List<NewsItem> items;
  int orderOpens = 0;
  int broadcastOpens = 0;
  final _orderCtrl = StreamController<List<NewsItem>>.broadcast();

  /// Сервердаги dismissed_news (барча қурилма учун умумий).
  final Set<String> dismissed = {};
  final _dismissedCtrl = StreamController<Set<String>>.broadcast();
  int dismissCalls = 0;

  @override
  Stream<Set<String>> watchDismissedIds(String userId) async* {
    yield {...dismissed};
    yield* _dismissedCtrl.stream;
  }

  @override
  Future<void> dismissNews(String userId, Iterable<String> newsIds) async {
    dismissCalls++;
    dismissed.addAll(newsIds);
    _dismissedCtrl.add({...dismissed});
  }

  void push(List<NewsItem> next) {
    items = next;
    _orderCtrl.add(next);
  }

  @override
  Stream<List<NewsItem>> watchOrderNews({String userId = '', int limit = 50}) {
    orderOpens++;
    return _orderCtrl.stream;
  }

  @override
  Stream<List<NewsItem>> watchBroadcastNews({
    List<String> audiences = const ['all'],
    String userId = '',
    int limit = 50,
  }) {
    broadcastOpens++;
    return Stream.value(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

NewsItem _order(String id, String orderId, DateTime at,
        {String status = 'accepted'}) =>
    NewsItem(
      id: id,
      title: 'Буюртма $orderId',
      body: 'x',
      createdAt: at,
      source: 'order_status',
      category: 'order',
      orderId: orderId,
      orderStatus: status,
      orderType: 'bread',
      targetUserId: '998901234567',
    );

void main() {
  final t0 = DateTime(2026, 10, 19, 10);

  setUp(() {
    SharedPreferences.setMockInitialValues({'user_phone': '998901234567'});
  });

  Future<_Repo> pumpOrders(
    WidgetTester t,
    _Repo repo, {
    NewsReadState read = NewsReadState.unknown,
    Key? hostKey,
  }) async {
    await t.pumpWidget(
      Provider<NewsRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(body: OrderNewsTab(readState: read)),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    return repo;
  }

  testWidgets(
      'рўйхат қайта чизилганда оқим қайта очилмайди ва spinner чиқмайди',
      (t) async {
    final repo = _Repo([_order('a', 'o1', t0)]);
    var tick = 0;
    late StateSetter host;
    await t.pumpWidget(
      Provider<NewsRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(builder: (ctx, set) {
              host = set;
              return OrderNewsTab(
                  readState: NewsReadState(
                      known: true,
                      readBefore: t0.add(Duration(minutes: tick))));
            }),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    repo.push([_order('a', 'o1', t0)]);
    await t.pump();
    expect(find.text('Буюртма o1'), findsOneWidget);
    expect(repo.orderOpens, 1);

    // «Хабарлар» экрани badge сабабли ҳар сафар қайта чизилади.
    for (var i = 0; i < 5; i++) {
      host(() => tick++);
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'spinner чиқмаслиги керак');
      expect(find.text('Буюртма o1'), findsOneWidget);
    }
    expect(repo.orderOpens, 1, reason: 'оқим фақат бир марта очилди');
  });

  FontWeight? weightOf(WidgetTester t, Finder card, String text) => t
      .widget<Text>(find.descendant(of: card, matching: find.text(text)))
      .style
      ?.fontWeight;

  testWidgets('ўқилмаган карта жирний, ўқилгани оддий шрифт', (t) async {
    final repo = _Repo([]);
    await pumpOrders(t, repo, read: NewsReadState(known: true, readBefore: t0));
    repo.push([
      _order('old', 'o-old', t0.subtract(const Duration(hours: 1))),
      _order('new', 'o-new', t0.add(const Duration(minutes: 5))),
    ]);
    await t.pump();
    final fresh = find.byKey(const ValueKey('order-news-o-new'));
    final stale = find.byKey(const ValueKey('order-news-o-old'));
    expect(fresh, findsOneWidget);
    expect(stale, findsOneWidget);
    expect(weightOf(t, fresh, 'Нон буюртма'), FontWeight.bold);
    expect(weightOf(t, fresh, 'Буюртма o-new'), FontWeight.bold);
    expect(weightOf(t, stale, 'Нон буюртма'), FontWeight.normal);
    expect(weightOf(t, stale, 'Буюртма o-old'), FontWeight.normal);
    expect(find.text('news_new_label'), findsNothing,
        reason: '«Янги» белгиси йўқ');
    expect(t.widget<Material>(fresh).color, t.widget<Material>(stale).color,
        reason: 'фон бир хил');
  });

  testWidgets('ҳолат номаълум бўлса ҳеч бир карта жирний эмас', (t) async {
    final repo = _Repo([]);
    await pumpOrders(t, repo);
    repo.push([_order('x', 'o-x', t0)]);
    await t.pump();
    expect(
        weightOf(
            t, find.byKey(const ValueKey('order-news-o-x')), 'Буюртма o-x'),
        FontWeight.normal);
  });

  testWidgets(
      'ўчириш: тасдиқдан кейин карта йўқолади ва қурилмада сақланади; бекор қилинса қолади',
      (t) async {
    final repo = _Repo([]);
    await pumpOrders(t, repo, read: NewsReadState(known: true, readBefore: t0));
    repo.push([
      _order('m1', 'o1', t0.add(const Duration(minutes: 1)), status: 'new'),
      _order('m2', 'o1', t0.add(const Duration(minutes: 2))),
      _order('m3', 'o2', t0.add(const Duration(minutes: 3))),
    ]);
    await t.pump();
    expect(find.byKey(const ValueKey('news-delete')), findsNWidgets(2));

    // Бекор қилинса — қолади.
    await t.tap(find.byKey(const ValueKey('news-delete')).first);
    await t.pumpAndSettle();
    await t.tap(find.text('news_delete_cancel'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('news-delete')), findsNWidgets(2));

    // Тасдиқланса — шу буюртманинг ҳамма хабарлари яширилади.
    await t.tap(find.byKey(const ValueKey('news-delete')).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('news-delete-confirm')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('news-delete')), findsOneWidget);
    expect(repo.dismissed, {'m3'}, reason: 'энг янги буюртма (o2) хабари сервер рўйхатига ёзилди; o1 қолди');
    expect(repo.dismissCalls, 1);

    // Сервердан шу хабар яна келса ҳам кўринмайди.
    repo.push(repo.items);
    await t.pump();
    expect(find.byKey(const ValueKey('news-delete')), findsOneWidget);
  });

  testWidgets('БОШҚА қурилма: сервердаги ўчирилганлар янги қурилмада ҳам кўринмайди (юклаш пайтидан)', (t) async {
    final repo = _Repo([]);
    repo.dismissed.addAll({'m1', 'm2'}); // бошқа қурилмада ўчирилган
    await pumpOrders(t, repo, read: NewsReadState(known: true, readBefore: t0));
    repo.push([
      _order('m1', 'o1', t0.add(const Duration(minutes: 1))),
      _order('m2', 'o1', t0.add(const Duration(minutes: 2))),
      _order('m3', 'o2', t0.add(const Duration(minutes: 3))),
    ]);
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('order-news-o1')), findsNothing);
    expect(find.byKey(const ValueKey('order-news-o2')), findsOneWidget);
  });

  testWidgets('умумий янгилик: жирний/оддий ва ўчириш', (t) async {
    final repo = _Repo([
      NewsItem(
          id: 'g1',
          title: 'Янгилик 1',
          body: 'b',
          createdAt: t0.add(const Duration(hours: 1))),
      NewsItem(
          id: 'g2',
          title: 'Эски янгилик',
          body: 'b',
          createdAt: t0.subtract(const Duration(days: 1))),
    ]);
    await t.pumpWidget(
      Provider<NewsRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
              body: GeneralNewsTab(
                  readState: NewsReadState(known: true, readBefore: t0))),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    expect(
        weightOf(t, find.byKey(const ValueKey('general-news-g1')), 'Янгилик 1'),
        FontWeight.bold);
    expect(
        weightOf(
            t, find.byKey(const ValueKey('general-news-g2')), 'Эски янгилик'),
        FontWeight.normal);
    await t.tap(find.byKey(const ValueKey('news-delete')).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('news-delete-confirm')));
    await t.pumpAndSettle();
    expect(find.text('Янгилик 1'), findsNothing);
    expect(find.text('Эски янгилик'), findsOneWidget);
    expect(repo.dismissed, {'g1'});
  });
}
