import 'package:ava_gurlan/features/realty/widgets/realty_video_sheet.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/models/realty_listing.dart';
import 'package:ava_gurlan/repositories/realty_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Видео варағи — modal bottom sheet. Унда snackbar варақ ОРТИДА қолади
/// (кўринмайди), шунинг учун хато варақнинг ичида кўрсатилиши керак.

class _Repo implements RealtyRepository {
  Object? linkError;
  Object? unlinkError;
  int links = 0;

  @override
  String get myOwnerPhone => '998901234567';

  @override
  Future<void> linkVideo({required String listingId, required String clipId}) async {
    links++;
    final e = linkError;
    if (e != null) throw e;
  }

  @override
  Future<void> unlinkVideo(String listingId) async {
    final e = unlinkError;
    if (e != null) throw e;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

TvClip _clip(String id) => TvClip(
      id: id,
      videoUrl: 'https://x/$id.mp4',
      posterUrl: '',
      title: 'Видео $id',
      price: 0,
      districtId: 'gurlan',
      districtLabel: 'Гурлан',
      ownerPhone: '998901234567',
      ownerName: 'Али',
      category: 'product',
      status: 'active',
      processingStatus: 'ready',
      createdAt: DateTime(2026, 10, 1),
    );

RealtyListing _listing({String? linkedClipId}) => RealtyListing(
      id: 'L1',
      ownerKey: 'k',
      ownerName: 'Али',
      deal: RealtyDeal.sale,
      tier: RealtyTier.plain,
      title: 'Уй',
      text: 'Тавсиф',
      areaLat: 41.8,
      areaLng: 60.4,
      status: 'active',
      avagramClipId: linkedClipId ?? '',
    );

Future<void> _open(WidgetTester t, _Repo repo, {String? linked}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<bool>(
            context: context,
            builder: (_) => RealtyVideoSheet(
              listing: _listing(linkedClipId: linked),
              repository: repo,
              loadClips: (_) async => [_clip('c1')],
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  const err = ValueKey('wallet-inline-error');
  const topUp = ValueKey('wallet-inline-error-topup');

  testWidgets('REGRESSION: боғлаш хатоси — варақ ИЧИДА (snackbar ортида қолмайди)', (t) async {
    final repo = _Repo()..linkError = const RealtyException('listing_blocked');
    await _open(t, repo);
    await t.tap(find.text('Видео c1'));
    await t.pumpAndSettle();
    expect(repo.links, 1);
    expect(find.byKey(err), findsOneWidget);
    expect(find.byKey(topUp), findsNothing);
    // Варақ ёпилмади — фойдаланувчи қайта уриниб кўра олади.
    expect(find.byType(RealtyVideoSheet), findsOneWidget);
  });

  testWidgets('баланс етмаса — хато ичида «Ҳамённи тўлдириш» тугмаси', (t) async {
    final repo = _Repo()..linkError = const RealtyException('insufficient_balance');
    await _open(t, repo);
    await t.tap(find.text('Видео c1'));
    await t.pumpAndSettle();
    expect(find.byKey(topUp), findsOneWidget);
  });

  testWidgets('REGRESSION: ажратиш хатоси аввал ЖИМ ютиларди — энди кўринади', (t) async {
    final repo = _Repo()..unlinkError = const RealtyException('listing_blocked');
    await _open(t, repo, linked: 'c1');
    await t.tap(find.byIcon(Icons.link_off));
    await t.pumpAndSettle();
    expect(find.byKey(err), findsOneWidget);
  });

  testWidgets('кутилмаган (RealtyException эмас) хато ҳам варақда умумий хабар', (t) async {
    final repo = _Repo()..linkError = StateError('boom');
    await _open(t, repo);
    await t.tap(find.text('Видео c1'));
    await t.pumpAndSettle();
    expect(find.byKey(err), findsOneWidget);
    expect(find.byKey(topUp), findsNothing);
  });

  testWidgets('муваффақиятли боғлаш — варақ ёпилади, хато йўқ', (t) async {
    final repo = _Repo();
    await _open(t, repo);
    await t.tap(find.text('Видео c1'));
    await t.pumpAndSettle();
    expect(find.byType(RealtyVideoSheet), findsNothing);
    expect(find.byKey(err), findsNothing);
  });
}
