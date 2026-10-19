// Таом видеоси (эга, 2026-10-19: «расм ёнига ихтиёрий видео, АВАГрамга ҳам жойлансин»):
// умумий видео қатлами (`tv_clips`, `TvClipLink`) таом даражасига кенгайтирилди.
// Қоида ваколати — `functions/test/tv_clip_link_rules.test.js` (K…N); бу ерда — клиент мантиғи.

import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/merchant/dish_video_tile.dart';
import 'package:ava_gurlan/features/restaurants/merchant/menu_item_form_screen.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_video_card.dart';
import 'package:ava_gurlan/features/restaurants/widgets/menu_item_video_badge.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_clip_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restaurants_l10n_harness.dart';

const _me = '998901234567';

TvClip _clip(
  String id, {
  String status = 'active',
  String processing = 'ready',
  String kind = 'restaurant_item',
  String linkId = 'r1',
  String itemId = 'osh',
  String owner = _me,
  DateTime? at,
  String reason = '',
}) =>
    TvClip(
      id: id,
      videoUrl: 'https://x/$id.mp4',
      posterUrl: '',
      title: 'Обзор $id',
      price: 0,
      districtId: 'gurlan',
      districtLabel: 'Гурлан',
      ownerPhone: owner,
      ownerName: 'Али',
      category: 'product',
      status: status,
      processingStatus: processing,
      createdAt: at ?? DateTime(2026, 10, 1),
      rejectReason: reason,
      linkKind: kind,
      linkId: linkId,
      linkItemId: itemId,
    );

void main() {
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);

  group('TvClip.linkItemId', () {
    test('toMap: таом боғлаши учта майдон билан; таомсиз турда linkItemId ёзилмайди', () {
      final m = _clip('a').toMap();
      expect(m['linkKind'], 'restaurant_item');
      expect(m['linkId'], 'r1');
      expect(m['linkItemId'], 'osh');
      final r = _clip('b', kind: 'restaurant', itemId: '').toMap();
      expect(r.containsKey('linkItemId'), isFalse);
      expect(r['linkKind'], 'restaurant');
    });

    test('боғлаш йўқ клип (kind/linkId бўш) — ҳеч қайси боғлаш майдони ёзилмайди', () {
      final m = _clip('c', kind: '', linkId: '', itemId: 'osh').toMap();
      expect(m.containsKey('linkKind'), isFalse);
      expect(m.containsKey('linkItemId'), isFalse, reason: 'боғлаш бўлмаса таом id ёлғиз ёзилмайди');
    });

    test('fromMap: эски ҳужжат (linkItemId йўқ) → бўш; ёзилган → ўқилади; toMap → fromMap айлантириб қайтади', () {
      expect(TvClip.fromMap('x', {'linkKind': 'restaurant', 'linkId': 'r1'}).linkItemId, '');
      final back = TvClip.fromMap('x', _clip('a').toMap());
      expect([back.linkKind, back.linkId, back.linkItemId], ['restaurant_item', 'r1', 'osh']);
    });

    test('isRestaurantLinked: ресторан ёки таом боғлаши (linkId билан); бошқа тур ёки бўш linkId — йўқ', () {
      expect(_clip('a').isRestaurantLinked, isTrue);
      expect(_clip('b', kind: 'restaurant', itemId: '').isRestaurantLinked, isTrue);
      expect(_clip('c', linkId: '').isRestaurantLinked, isFalse, reason: 'linkId бўш — ресторан номаълум');
      expect(_clip('d', kind: 'ad', itemId: '').isRestaurantLinked, isFalse);
      expect(_clip('e', kind: 'wholesale_product', itemId: '').isRestaurantLinked, isFalse);
      expect(_clip('f', kind: '', linkId: '', itemId: '').isRestaurantLinked, isFalse);
    });

    test('copyWith linkItemId', () {
      expect(_clip('a').copyWith(linkItemId: 'somsa').linkItemId, 'somsa');
      expect(_clip('a').copyWith().linkItemId, 'osh');
    });
  });

  group('pickRestaurantItemClips — мижоз менюси учун таом → клип', () {
    test('ҳар таомга ЭНГ ЯНГИ фаол клип', () {
      final out = pickRestaurantItemClips([
        _clip('old', at: DateTime(2026, 10, 1)),
        _clip('new', at: DateTime(2026, 10, 5)),
        _clip('s', itemId: 'somsa'),
      ]);
      expect(out.keys.toSet(), {'osh', 'somsa'});
      expect(out['osh']!.id, 'new');
    });

    test('ресторан видеоси, таом id\'сиз, фаол бўлмаган ва ўйнатилмайдиган клиплар ҳисобга олинмайди', () {
      final out = pickRestaurantItemClips([
        _clip('rest', kind: 'restaurant', itemId: ''),
        _clip('noitem', itemId: ''),
        _clip('pending', status: 'pending', itemId: 'a'),
        _clip('blocked', status: 'blocked', itemId: 'b'),
        _clip('err', processing: 'error', itemId: 'c'),
        _clip('ok', itemId: 'd'),
      ]);
      expect(out.keys, ['d']);
    });

    test('бўш рўйхат → бўш харита', () {
      expect(pickRestaurantItemClips(const []), isEmpty);
    });

    test('эгалик солиштирилмайди: ходим юклаган клип ҳам кўринади (ваколат қоидада)', () {
      expect(pickRestaurantItemClips([_clip('staff', owner: '998905554433')]).keys, ['osh']);
    });
  });

  group('TvClipLink.publish — таом видеоси', () {
    testWidgets('таом id\'сиз restaurant_item жойлаш очилмайди (клип ресторан видеосига ўхшаб қолмасин)', (t) async {
      bool? result;
      await t.pumpWidget(l10nApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async =>
                result = await TvClipLink.publish(Navigator.of(ctx), kind: TvClipLink.kindRestaurantItem, linkId: 'r1'),
            child: const Text('go'),
          ),
        ),
      ));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(result, isFalse);
      expect(find.byType(TextButton), findsOneWidget, reason: 'экран очилмади');
    });

    testWidgets('ресторан id бўш — очилмайди', (t) async {
      bool? result;
      await t.pumpWidget(l10nApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result = await TvClipLink.publish(Navigator.of(ctx),
                kind: TvClipLink.kindRestaurantItem, linkId: '', linkItemId: 'osh'),
            child: const Text('go'),
          ),
        ),
      ));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(result, isFalse);
    });
  });

  group('MenuItemVideoBadge', () {
    testWidgets('босиш майдони ≥ 44, босилса чақиради, экран ўқувчи учун «Videoni ko‘rish» белгиси', (t) async {
      var taps = 0;
      await t.pumpWidget(l10nApp(
        home: Scaffold(body: Center(child: MenuItemVideoBadge(itemId: 'osh', onTap: () => taps++))),
      ));
      final size = t.getSize(find.byKey(const ValueKey('item-video-osh')));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.bySemanticsLabel(tr('link_video_open')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('item-video-osh')));
      expect(taps, 1);
    });
  });

  group('RestaurantVideoCard — таом режими', () {
    Future<void> pumpCard(
      WidgetTester t, {
      String itemId = '',
      required Future<List<TvClip>> Function() loader,
      Future<bool> Function()? publisher,
    }) async {
      await t.pumpWidget(l10nApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RestaurantVideoCard(
              key: UniqueKey(), // ҳар чақирувда ЯНГИ ҳолат (initState қайта ишлайди)
              restaurantId: 'r1',
              ownerPhone: _me,
              currentPhone: _me,
              restaurantApproved: true,
              linkItemId: itemId,
              loader: loader,
              publisher: publisher,
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('таом: ўз сарлавҳаси ва изоҳи (АВАГрам + тармоқлар), алоҳида калит; ресторан режимида — эскича', (t) async {
      await pumpCard(t, itemId: 'osh', loader: () async => const []);
      expect(find.byKey(const ValueKey('dish-video-card')), findsOneWidget);
      expect(find.text(tr('restaurants_m_dish_video_title')), findsOneWidget);
      expect(find.textContaining('Instagram'), findsOneWidget, reason: 'тармоқ танлови борлиги эгага айтилади');
      expect(find.text(tr('restaurants_m_video_title')), findsNothing);

      await pumpCard(t, loader: () async => const []);
      expect(find.byKey(const ValueKey('restaurant-video-card')), findsOneWidget);
      expect(find.text(tr('restaurants_m_video_title')), findsOneWidget);
    });

    testWidgets('таом: «қўшиш» ва ҳолат; бўш бўлса «қўшиш», бор бўлса «алмаштириш»', (t) async {
      await pumpCard(t, itemId: 'osh', loader: () async => const []);
      expect(find.text(tr('restaurants_m_video_add')), findsOneWidget);
      await pumpCard(t, itemId: 'osh', loader: () async => [_clip('c1', status: 'pending')]);
      expect(find.byKey(const ValueKey('video-status-pending')), findsOneWidget);
      expect(find.text(tr('restaurants_m_video_replace')), findsOneWidget);
    });

    testWidgets('жойлаш чақирилади ва муваффақиятда рўйхат қайта юкланади', (t) async {
      var loads = 0;
      var published = 0;
      await pumpCard(
        t,
        itemId: 'osh',
        loader: () async {
          loads += 1;
          return const [];
        },
        publisher: () async {
          published += 1;
          return true;
        },
      );
      expect(loads, 1);
      await t.tap(find.byKey(const ValueKey('video-publish')));
      await t.pumpAndSettle();
      expect(published, 1);
      expect(loads, 2);
    });
  });

  group('DishVideoTile', () {
    Future<void> pumpTile(
      WidgetTester t, {
      String? itemId,
      required Future<String?> Function() ensureSaved,
      Future<List<TvClip>> Function(String itemId)? loader,
      Future<bool> Function(String itemId)? publisher,
      double textScale = 1.0,
      double size = 140,
    }) async {
      await t.pumpWidget(l10nApp(
        textScale: textScale,
        home: Scaffold(
          body: Center(
            child: DishVideoTile(
              key: UniqueKey(),
              restaurantId: 'r1',
              ownerPhone: _me,
              currentPhone: _me,
              restaurantApproved: true,
              itemId: itemId,
              ensureSaved: ensureSaved,
              size: size,
              loader: loader ?? (_) async => const [],
              publisher: publisher,
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('видеоси йўқ — «Video qo\'shish»; ҳолатлар: фаол / текширувда / рад / хато (қисқа ёрлиқ + иконка)', (t) async {
      await pumpTile(t, itemId: 'osh', ensureSaved: () async => 'osh');
      expect(find.text(tr('restaurants_m_dish_video_add')), findsOneWidget);
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);

      final cases = {
        'active': (Icons.play_circle_fill_rounded, _clip('a')),
        'pending': (Icons.hourglass_top_rounded, _clip('p', status: 'pending')),
        'blocked': (Icons.error_outline_rounded, _clip('b', status: 'blocked')),
        'error': (Icons.error_outline_rounded, _clip('e', processing: 'error')),
      };
      for (final e in cases.entries) {
        await pumpTile(t, itemId: 'osh', ensureSaved: () async => 'osh', loader: (_) async => [e.value.$2]);
        expect(find.text(tr('restaurants_m_dish_video_st_${e.key}')), findsOneWidget, reason: e.key);
        expect(find.byIcon(e.value.$1), findsOneWidget, reason: e.key);
      }
    });

    testWidgets('таом ҲАЛИ сақланмаган: босилса ensureSaved чақирилади; null (хато) — варақ очилмайди', (t) async {
      var saves = 0;
      await pumpTile(t, ensureSaved: () async {
        saves += 1;
        return null;
      });
      await t.tap(find.byKey(const ValueKey('dish-video-tile')));
      await t.pumpAndSettle();
      expect(saves, 1);
      expect(find.byKey(const ValueKey('dish-video-card')), findsNothing, reason: 'сақлаб бўлмади — видео очилмайди');
    });

    testWidgets('сақлаш муваффақиятли: варақ очилади ва жойлаш ШУ таом id\'си билан чақирилади', (t) async {
      String? publishedFor;
      var saves = 0;
      await pumpTile(
        t,
        ensureSaved: () async {
          saves += 1;
          return 'new-dish-1';
        },
        publisher: (id) async {
          publishedFor = id;
          return false;
        },
      );
      await t.tap(find.byKey(const ValueKey('dish-video-tile')));
      await t.pumpAndSettle();
      expect(saves, 1);
      expect(find.byKey(const ValueKey('dish-video-card')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('video-publish')));
      await t.pumpAndSettle();
      expect(publishedFor, 'new-dish-1');

      // Варақ ёпилгач иккинчи босишда таом ҚАЙТА сақланмайди (ID маълум)
      await t.tapAt(const Offset(5, 5)); // scrim
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('dish-video-tile')));
      await t.pumpAndSettle();
      expect(saves, 1, reason: 'таом бир марта яратилди');
    });

    testWidgets('сақланган таом: сақлашсиз тўғридан-тўғри варақ; варақ ёпилгач ҳолат янгиланади', (t) async {
      var loads = 0;
      await pumpTile(
        t,
        itemId: 'osh',
        ensureSaved: () async => fail('сақланган таомда ensureSaved чақирилмайди'),
        loader: (_) async {
          loads += 1;
          return loads >= 3 ? [_clip('c', status: 'pending')] : const [];
        },
      );
      expect(loads, 1);
      await t.tap(find.byKey(const ValueKey('dish-video-tile')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-video-card')), findsOneWidget);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(loads, greaterThanOrEqualTo(3), reason: 'ёпилгач катак ҳолати қайта юкланди');
      expect(find.text(tr('restaurants_m_dish_video_st_pending')), findsOneWidget);
    });

    testWidgets('тор катак (120) ва шрифт ×2 да синмайди', (t) async {
      t.view.physicalSize = const Size(320 * 3, 640 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await pumpTile(
        t,
        itemId: 'osh',
        ensureSaved: () async => 'osh',
        loader: (_) async => [_clip('b', status: 'blocked')],
        textScale: 2.0,
        size: 120,
      );
      expect(t.takeException(), isNull);
    });
  });

  group('MenuItemFormScreen + видео катаги', () {
    Future<void> openForm(WidgetTester t, _Repo repo, {String? ownerPhone = _me, MenuItem? existing, double width = 390}) async {
      t.view.physicalSize = Size(width * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => MenuItemFormScreen(
                restaurantId: 'r1',
                categories: const [],
                repository: repo,
                existing: existing,
                ownerPhone: ownerPhone,
                videoLoader: (_) async => const [],
                videoPublisher: (id) async {
                  repo.videoFor.add(id);
                  return false;
                },
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    Finder field(String key) => find.widgetWithText(TextField, tr(key));

    testWidgets('ownerPhone берилмаса (эски чақирув) — катак ва изоҳ йўқ', (t) async {
      await openForm(t, _Repo(), ownerPhone: null);
      expect(find.byKey(const ValueKey('dish-video-tile')), findsNothing);
      expect(find.text(tr('restaurants_m_dish_video_save_hint')), findsNothing);
    });

    testWidgets('янги таом: расм ёнида катак ва «аввал сақланади» изоҳи; ном/нарх бўлмаса босилганда хато, таом ЯРАТИЛМАЙДИ', (t) async {
      final repo = _Repo();
      await openForm(t, repo);
      expect(find.byKey(const ValueKey('dish-video-tile')), findsOneWidget);
      expect(find.text(tr('restaurants_m_dish_video_save_hint')), findsOneWidget);
      // расм ва видео катаклари ёнма-ён (бир қаторда)
      final photoY = t.getTopLeft(find.text(tr('restaurants_m_item_photo'))).dy;
      final videoY = t.getTopLeft(find.byKey(const ValueKey('dish-video-tile'))).dy;
      expect((photoY - videoY).abs(), lessThan(140), reason: 'бир қатор: расм ёзуви ва катак');

      await t.tap(find.byKey(const ValueKey('dish-video-tile')));
      await t.pumpAndSettle();
      expect(repo.upserts, isEmpty);
      expect(find.text(tr('restaurants_m_err_item')), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-video-card')), findsNothing);
    });

    testWidgets('ном ва нарх бор: босилса таом САҚЛАНАДИ (янги id), варақ очилади, жойлаш шу id билан; «Сақлаш» ҳужжатни ЯНГИЛАЙДИ (иккинчи таом яратилмайди)', (t) async {
      final repo = _Repo();
      await openForm(t, repo);
      await t.enterText(field('restaurants_m_item_name'), 'Osh');
      await t.enterText(field('restaurants_m_item_price'), '35000');
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('dish-video-tile')));
      await t.pumpAndSettle();
      expect(repo.upserts.map((u) => u.id), [null], reason: 'биринчи сақлаш — янги ҳужжат');
      expect(find.byKey(const ValueKey('dish-video-card')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('video-publish')));
      await t.pumpAndSettle();
      expect(repo.videoFor, ['dish-1']);

      await t.tapAt(const Offset(5, 5)); // варақни ёпиш
      await t.pumpAndSettle();
      expect(find.text(tr('restaurants_m_dish_video_save_hint')), findsNothing, reason: 'таом сақланди — изоҳ керак эмас');

      await t.enterText(field('restaurants_m_item_price'), '36000');
      await t.ensureVisible(find.widgetWithText(FilledButton, tr('restaurants_m_save')));
      await t.tap(find.widgetWithText(FilledButton, tr('restaurants_m_save')));
      await t.pumpAndSettle();
      expect(repo.upserts.map((u) => u.id), [null, 'dish-1'], reason: 'иккинчи сақлаш ШУ ҳужжатни янгилайди');
      expect(repo.upserts.last.price, 36000);
      expect(repo.upserts.last.sort, repo.upserts.first.sort, reason: 'таом тартиби ўзгармайди');
      expect(find.text('open'), findsOneWidget, reason: 'форма ёпилди');
    });

    testWidgets('сақланган таомни таҳрирлаш: катак бор, изоҳ йўқ, босилса сақлашсиз варақ очилади', (t) async {
      final repo = _Repo();
      await openForm(t, repo, existing: const MenuItem(id: 'osh', name: 'Osh', price: 35000));
      expect(find.text(tr('restaurants_m_dish_video_save_hint')), findsNothing);
      await t.tap(find.byKey(const ValueKey('dish-video-tile')));
      await t.pumpAndSettle();
      expect(repo.upserts, isEmpty, reason: 'таом аллақачон бор — қайта сақланмайди');
      expect(find.byKey(const ValueKey('dish-video-card')), findsOneWidget);
    });

    testWidgets('тор экран 320: расм ва видео катаклари ёнма-ён сиғади (overflow йўқ)', (t) async {
      await openForm(t, _Repo(), width: 320);
      expect(t.takeException(), isNull);
      final photo = t.getRect(find.byType(InkWell).first);
      final video = t.getRect(find.byKey(const ValueKey('dish-video-tile')));
      expect(video.left, greaterThanOrEqualTo(photo.right), reason: 'ёнма-ён');
      expect(video.right, lessThanOrEqualTo(320));
    });
  });
}

class _Upsert {
  _Upsert(this.id, this.price, this.sort);
  final String? id;
  final int price;
  final int sort;
}

class _Repo implements RestaurantsRepository {
  final upserts = <_Upsert>[];
  final videoFor = <String>[];

  @override
  Future<String> upsertMenuItem(
    String restaurantId, {
    String? id,
    required String name,
    required int price,
    String description = '',
    String photoUrl = '',
    String categoryId = '',
    int sort = 0,
    bool available = true,
    DateTime? stopUntil,
    covariant Object? facts,
    covariant Object? qtyTiers,
  }) async {
    upserts.add(_Upsert(id, price, sort));
    return id ?? 'dish-${upserts.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}
