import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import '../../tv_market/screens/tv_market_feed_screen.dart';
import '../../tv_market/screens/tv_publish_screen.dart';
import '../repositories/wholesale_products_repository.dart';

/// Улгуржи маҳсулот ↔ AVAGram клипи боғланиши.
///
/// Видео мавжуд `TvPublishScreen`да нашр қилинади (сотувчи ўзи «Маҳсулот»
/// = органик ёки «Реклама» = пуллик танлайди); кейин икки томонлама боғланади:
///   - `wholesale_products.videoClipIds` ← clipId
///   - `tv_clips.wholesaleProductId` ← productId (лентадаги «Улгуржи» тугмаси)
class WholesaleVideoLink {
  WholesaleVideoLink._();

  /// Нашр экранини очади; муваффақиятли бўлса энг сўнгги (бошқа маҳсулотга
  /// боғланмаган) клипни [productId]га боғлайди. `true` — боғланди.
  static Future<bool> publishAndLink(
    BuildContext context, {
    required String sellerPhone,
    required String productId,
  }) async {
    final published = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const TvPublishScreen(hideShopOption: true),
      ),
    );
    if (published != true) return false;

    final clips = await TvClipsRepository().fetchByOwner(sellerPhone, limit: 5);
    TvClip? fresh;
    for (final c in clips) {
      final other = c.wholesaleProductId;
      if (other.isEmpty || other == productId) {
        fresh = c;
        break;
      }
    }
    if (fresh == null) return false;

    await WholesaleProductsRepository().addVideoClip(productId, fresh.id);
    // Rules: эга ўз клипида blacklist'дан ташқари майдонни янгилай олади.
    try {
      await FirebaseFirestore.instance
          .collection('tv_clips')
          .doc(fresh.id)
          .update({'wholesaleProductId': productId});
    } catch (_) {
      // Best-effort — асосий боғланиш (videoClipIds) аллақачон ёзилди.
    }
    return true;
  }

  /// [clipIds] ичидан биринчи мавжуд (ўчирилмаган) клипни топади.
  static Future<TvClip?> findLinkedClip({
    required String sellerPhone,
    required List<String> clipIds,
  }) async {
    if (clipIds.isEmpty) return null;
    final clips = await TvClipsRepository().fetchByOwner(sellerPhone);
    for (final id in clipIds) {
      final hit = clips.where((c) => c.id == id);
      if (hit.isNotEmpty) return hit.first;
    }
    return null;
  }

  /// Боғланган видеони AVAGram лентасида очади.
  static Future<bool> openLinkedClip(
    BuildContext context, {
    required String sellerPhone,
    required List<String> clipIds,
  }) async {
    final clip =
        await findLinkedClip(sellerPhone: sellerPhone, clipIds: clipIds);
    if (clip == null || !context.mounted) return false;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TvMarketFeedScreen(initialClip: clip)),
    );
    return true;
  }
}
