import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/ads/models/ad_model.dart';
import 'package:ava_gurlan/features/ads/repositories/ads_repository.dart';
import 'package:ava_gurlan/features/my_shop/widgets/shop_ads_catalog.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_clip_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// «Менинг дўконим» → Аҳоли бозори каталоги: ҳар маҳсулот расм ва ВИДЕО билан.
/// Локализация делегати АТАЙЛАБ уланмаган: `context.tr` калитнинг ўзини қайтаради.

class _FakeAdsRepo extends Fake implements AdsRepository {}

AdModel _ad(String id, String title, int price, {String status = 'active'}) => AdModel(
      id: id,
      ownerId: '998901234567',
      title: title,
      titleLower: title.toLowerCase(),
      description: '',
      price: price,
      phone: '998901234567',
      sellerName: 'Shop',
      imageUrls: const [],
      status: status,
      views: 0,
    );

TvClip _clip(String adId, {String status = 'active', String processing = 'ready'}) => TvClip(
      id: 'clip-$adId',
      videoUrl: 'https://x/v.mp4',
      posterUrl: '',
      title: 'v',
      price: 0,
      districtId: '',
      districtLabel: '',
      ownerPhone: '998901234567',
      ownerName: 'Shop',
      category: 'ad',
      status: status,
      processingStatus: processing,
      linkKind: TvClipLink.kindMarket,
      linkId: adId,
    );

void main() {
  final shoes = _ad('a1', 'Kross', 350000);
  final bag = _ad('a2', 'Sumka', 180000);
  final cap = _ad('a3', 'Kepka', 60000, status: 'pending');

  Future<void> open(
    WidgetTester tester, {
    Map<String, List<AdModel>>? byStatus,
    Future<Map<String, TvClip>> Function(String)? clips,
    Future<void> Function(BuildContext, AdModel)? onAdd,
    void Function(BuildContext, TvClip)? onOpen,
    Stream<List<AdModel>> Function(String)? stream,
  }) async {
    tester.view.physicalSize = const Size(400 * 2, 1400 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final data = byStatus ??
        {
          'active': [shoes, bag],
          'pending': [cap],
          'inactive': <AdModel>[],
        };
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Provider<AdsRepository>.value(
        value: _FakeAdsRepo(),
        child: Scaffold(
          body: ShopAdsCatalog(
            key: UniqueKey(),
            uid: '998901234567',
            adsStream: stream ?? (s) => Stream.value(data[s] ?? const []),
            loadClips: clips ?? (_) async => {'a1': _clip('a1')},
            onAddVideo: onAdd ?? (_, __) async {},
            onOpenVideo: onOpen ?? (_, __) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('каталог: ном ва нарх; видеоли маҳсулотда «Видеони кўриш», видеосизда «Видео қўшиш»', (tester) async {
    await open(tester);
    expect(find.text('Kross'), findsOneWidget);
    expect(find.text('Sumka'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
    expect(find.text('link_video_open'), findsOneWidget);
    expect(find.text('my_shop_video_add'), findsOneWidget);
  });

  testWidgets('«Видео қўшиш» — худди шу эълон билан чақирилади', (tester) async {
    AdModel? added;
    await open(tester, onAdd: (_, ad) async => added = ad);
    await tester.tap(find.text('my_shop_video_add'));
    await tester.pumpAndSettle();
    expect(added?.id, 'a2');
  });

  testWidgets('«Видеони кўриш» — шу эълоннинг клипини очади', (tester) async {
    TvClip? opened;
    await open(tester, onOpen: (_, clip) => opened = clip);
    await tester.tap(find.text('link_video_open'));
    await tester.pumpAndSettle();
    expect(opened?.id, 'clip-a1');
  });

  testWidgets('текширувдаги видео — кутиш белгиси, босилмайди', (tester) async {
    await open(tester, clips: (_) async => {'a1': _clip('a1', status: 'pending')});
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    expect(find.text('link_video_open'), findsNothing);
  });

  testWidgets('рад этилган/ишламаган видео — яна «Видео қўшиш» таклиф қилинади', (tester) async {
    await open(tester, clips: (_) async => {'a1': _clip('a1', status: 'blocked')});
    expect(find.text('my_shop_video_add'), findsNWidgets(2));
    expect(find.text('link_video_open'), findsNothing);
  });

  testWidgets('клиплар ўқилмаса — каталог ишлайди, видео тугмаси «қўшиш» бўлиб қолади', (tester) async {
    await open(tester, clips: (_) async => throw StateError('offline'));
    expect(find.text('Kross'), findsOneWidget);
    expect(find.text('my_shop_video_add'), findsNWidgets(2));
  });

  testWidgets('бўш ҳолат: маҳсулот йўқ — тушунарли матн', (tester) async {
    await open(tester, byStatus: {'active': [], 'pending': [], 'inactive': []});
    expect(find.text('my_shop_catalog_empty'), findsOneWidget);
  });

  testWidgets('рўйхат ўқилмаса — «бўш» эмас, хато жумласи (хато матни йўқ)', (tester) async {
    await open(tester, stream: (_) => Stream<List<AdModel>>.error(StateError('permission-denied')));
    expect(find.text('cheap_products_load_error'), findsOneWidget);
    expect(find.text('my_shop_catalog_empty'), findsNothing);
    expect(find.text('permission-denied'), findsNothing);
  });

  testWidgets('«Текширувда» табида — кутиш белгиси, амаллар менюси йўқ', (tester) async {
    await open(tester);
    expect(find.byType(PopupMenuButton<String>), findsNWidgets(2)); // фаол: 2 та маҳсулот
    await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('jobs_status_pending')));
    await tester.pumpAndSettle();
    expect(find.text('Kepka'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top), findsWidgets);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('видео боғланганда (TvClipLink.changes) клиплар қайта ўқилади', (tester) async {
    var calls = 0;
    await open(tester, clips: (_) async {
      calls++;
      return calls == 1 ? <String, TvClip>{} : {'a1': _clip('a1')};
    });
    expect(find.text('link_video_open'), findsNothing);
    TvClipLink.changes.value++;
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('link_video_open'), findsOneWidget);
  });
}
