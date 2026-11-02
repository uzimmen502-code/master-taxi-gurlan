// AVAGram: ўз видеосидаги «Таҳрирлаш» / «Ўчириш» — 44 → 26 px (эга, 2026-11-03: 40% кичик).
import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_clip_overlay.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_owner_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('баландлик 26 px (44 нинг 60%), тугмалар ишлайди, матн тошмайди', (t) async {
    var edit = 0, del = 0;
    await t.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: TvOwnerActionBar(onEdit: () => edit++, onDelete: () => del++)),
      ),
    ));
    expect(TvOwnerActionBar.defaultHeight, closeTo(44 * 0.6, 0.5));
    expect(t.getSize(find.byKey(const ValueKey('tv-owner-edit'))).height, 26);
    expect(t.getSize(find.byKey(const ValueKey('tv-owner-delete'))).height, 26);
    expect(t.takeException(), isNull, reason: 'RenderFlex overflow йўқ');
    await t.tap(find.byKey(const ValueKey('tv-owner-edit')));
    await t.tap(find.byKey(const ValueKey('tv-owner-delete')));
    expect((edit, del), (1, 1));
  });

  testWidgets('лента устида: эгасига кўринади, бегонага йўқ', (t) async {
    TvClip clip() => const TvClip(
          id: 'c1',
          videoUrl: 'https://example.test/a.mp4',
          posterUrl: '',
          title: 'Сотилади',
          price: 0,
          districtId: 'd1',
          districtLabel: 'Гурлан',
          ownerPhone: '+998900000000',
          ownerName: 'Аваз',
          category: 'product',
        );
    Future<void> pump(bool owner) => t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Stack(children: [
              TvClipOverlay(
                clip: clip(),
                isOwner: owner,
                onEdit: () {},
                onDelete: () {},
                onContact: () {},
                onLike: () {},
                onComment: () {},
                onShare: () {},
                onSave: () {},
              ),
            ]),
          ),
        ));
    await pump(true);
    expect(find.byType(TvOwnerActionBar), findsOneWidget);
    expect(t.getSize(find.byType(TvOwnerActionBar)).height, 26);
    await pump(false);
    expect(find.byType(TvOwnerActionBar), findsNothing);
  });
}
