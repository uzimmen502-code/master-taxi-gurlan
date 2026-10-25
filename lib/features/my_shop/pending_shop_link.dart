import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../business_map/data/business_repository.dart';
import '../restaurants/open_restaurant_checked.dart';
import '../tv_market/screens/tv_shop_public_screen.dart';

/// Веб-ҳаволадан келган дўкон (`/?shop=<publicId>`, 5-босқич): `/s/<id>` саҳифасидаги «Дўконни очиш» тугмаси
/// Flutter веб-иловани шу параметр билан очади. Ишга тушишда ушланади ([captureFromUrl]) ва бош саҳифа очилгач
/// (логиндан кейин ҳам) бир марта ишлатилади ([openIfAny]). Блокланган/номаълум — «вақтинча мавжуд эмас».
class PendingShopLink {
  PendingShopLink._();

  static final _idRe = RegExp(r'^[A-Za-z0-9]{10}$');
  static String? _id;

  /// Статистика манбаи: QR-коддан (`qr`) ёки улашилган ҳаволадан (`link`).
  static String _source = 'link';

  /// [uri] — тест учун; бўлмаса вебда `Uri.base`. Мобил иловада ҳозирча ҳеч нарса қилмайди (App Links — APK).
  static void captureFromUrl([Uri? uri]) {
    if (uri == null && !kIsWeb) return;
    final q = (uri ?? Uri.base).queryParameters;
    final id = q['shop']?.trim() ?? '';
    if (_idRe.hasMatch(id)) {
      _id = id;
      _source = q['src'] == 'qr' ? 'qr' : 'link';
    }
  }

  @visibleForTesting
  static String get source => _source;

  /// Бир марта олинади (қайта очилмасин).
  static String? take() {
    final v = _id;
    _id = null;
    return v;
  }

  /// [openRestaurant] — тест учун; бўлмаса [openRestaurantChecked] (ҳолат очиш вақтида қайта текширилади).
  static Future<void> openIfAny(
    BuildContext context, {
    Future<({String ownerPhone, String businessId, String restaurantId})?> Function(String publicId)? resolve,
    void Function(Widget screen)? push,
    Future<void> Function(BuildContext context, String restaurantId, String source)? openRestaurant,
  }) async {
    final id = take();
    if (id == null) return;
    ({String ownerPhone, String businessId, String restaurantId})? target;
    try {
      target = await (resolve ?? BusinessRepository().resolveShopLink)(id);
    } catch (e) {
      debugPrint('[PendingShopLink] resolve: $e');
    }
    if (!context.mounted) return;
    // Кафе-ресторан ҳаволаси (2026-10-25): ўша `/s/<id>` → ўша параметр, фақат очиладиган объект бошқа.
    if (target != null && target.restaurantId.isNotEmpty) {
      final open = openRestaurant ??
          (c, rid, src) => openRestaurantChecked(c, rid, source: src, push: push);
      return open(context, target.restaurantId, _source);
    }
    if (target == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('shop_unavailable'))));
      return;
    }
    final screen = TvShopPublicScreen(ownerPhone: target.ownerPhone, businessId: target.businessId, source: _source);
    if (push != null) return push(screen);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}
