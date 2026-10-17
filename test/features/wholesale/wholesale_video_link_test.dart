import 'dart:io';

import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_clip_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Улгуржи видео боғлаш (эга қабул қилган таклиф, 2026-10-17): «энг сўнгги
/// клип»ни тахмин қилиш ЎРНИГА — яратилган клипнинг аниқ ID'си билан.
///
/// `WholesaleVideoLink` Navigator ва Firestore билан ишлайди (Firebase'сиз
/// ишга тушмайди), шунинг учун қарор мантиғи икки қатламда текширилади:
/// маълумот модели (`TvClip`) ва манба-даражадаги қўриқчи (тахмин қайтиб
/// келмасин).
void main() {
  test('kindWholesale — барқарор қиймат (клипларда сақланади)', () {
    expect(TvClipLink.kindWholesale, 'wholesale_product');
  });

  test('ID бўйича боғланган клип: linkKind/linkId/wholesaleProductId ёзилади', () {
    final clip = TvClip(
      id: '',
      videoUrl: 'https://x/v.mp4',
      posterUrl: '',
      title: 'Видео',
      price: 0,
      districtId: 'gurlan',
      districtLabel: 'Гурлан',
      ownerPhone: '998901112233',
      ownerName: 'Сотувчи',
      category: 'product',
      status: 'active',
      linkKind: TvClipLink.kindWholesale,
      linkId: 'prod1',
      wholesaleProductId: 'prod1',
    );
    final m = clip.toMap();
    expect(m['linkKind'], 'wholesale_product');
    expect(m['linkId'], 'prod1');
    expect(m['wholesaleProductId'], 'prod1');
  });

  test('қўриқчи: wholesale_video_link.dart тахминга қайтмайди', () {
    final src = File('lib/features/wholesale/services/wholesale_video_link.dart')
        .readAsStringSync();
    // Эски тахмин: эгасининг сўнгги 5 клипидан биринчи бўшини олиш.
    expect(src.contains('fetchByOwner(sellerPhone, limit: 5)'), isFalse,
        reason: '«энг сўнгги клип» тахмини қайтмасин');
    // Янги йўл: нашр экрани ID қайтаради ва боғлаш шу ID бўйича.
    expect(src.contains('onClipCreated'), isTrue);
    expect(src.contains('TvClipLink.kindWholesale'), isTrue);
    expect(src.contains("'linkKind'"), isTrue);
  });

  test('қўриқчи: нашр экрани ID ни ҳам оддий, ҳам пуллик йўлда беради', () {
    final src = File('lib/features/tv_market/screens/tv_publish_screen.dart')
        .readAsStringSync();
    // Оддий видео: tv_clips.add дан кейин; пуллик реклама: CF жавоби (clipId).
    expect(src.contains('widget.onClipCreated?.call(clipRef.id)'), isTrue);
    expect(src.contains("result['clipId']"), isTrue);
  });
}
