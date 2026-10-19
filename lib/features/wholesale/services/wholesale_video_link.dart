import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import '../../tv_market/screens/tv_market_feed_screen.dart';
import '../../tv_market/services/tv_clip_link.dart';
import '../repositories/wholesale_products_repository.dart';

/// Улгуржи маҳсулот ↔ AVAGram клипи боғланиши.
///
/// Видео мавжуд `TvPublishScreen`да нашр қилинади (сотувчи ўзи «Маҳсулот»
/// = органик ёки «Реклама» = пуллик танлайди); кейин икки томонлама боғланади:
///   - `wholesale_products.videoClipIds` ← clipId
///   - `tv_clips.wholesaleProductId` ← productId (лентадаги «Улгуржи» тугмаси)
class WholesaleVideoLink {
  WholesaleVideoLink._();

  /// Нашр экранини очади; муваффақиятли бўлса ЯНГИ яратилган клипни (унинг ID'си
  /// нашр экранидан келади) [productId]га боғлайди. `true` — боғланди.
  ///
  /// Аввал «энг сўнгги, бошқа маҳсулотга боғланмаган клип» деб тахмин
  /// қилинарди — бир вақтда бошқа клип чиқса ёки ҳисоб кечикса адашиши
  /// мумкин эди. Энди боғлаш аниқ ID бўйича (оддий видеода клипнинг ўзига
  /// `linkKind`/`linkId` яратилганда ёзилади, Аҳоли бозоридаги каби).
  static Future<bool> publishAndLink(
    BuildContext context, {
    required String sellerPhone,
    required String productId,
  }) async {
    String? clipId;
    // Жойлаш — ЯГОНА қатлам ([TvClipLink.publish]); Улгуржида пуллик «Реклама» ҳам бор (`organicOnly: false`).
    final published = await TvClipLink.publish(
      Navigator.of(context),
      kind: TvClipLink.kindWholesale,
      linkId: productId,
      organicOnly: false,
      onClipCreated: (id) => clipId = id,
    );
    final id = clipId;
    if (!published || id == null || id.isEmpty) return false;

    await WholesaleProductsRepository().addVideoClip(productId, id);
    // Rules: эга ўз клипида blacklist'дан ташқари майдонни янгилай олади.
    // Пуллик реклама клипини CF яратади (`linkKind` у ерда ёзилмайди) —
    // шунинг учун иккала турда ҳам боғлаш майдонлари ID бўйича тасдиқланади.
    try {
      await FirebaseFirestore.instance.collection('tv_clips').doc(id).update({
        'wholesaleProductId': productId,
        'linkKind': TvClipLink.kindWholesale,
        'linkId': productId,
      });
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
