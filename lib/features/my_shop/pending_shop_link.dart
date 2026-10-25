import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../business_map/data/business_repository.dart';
import '../restaurants/open_restaurant_checked.dart';
import '../tv_market/screens/tv_shop_public_screen.dart';

/// Веб-ҳаволадан келган дўкон (`/?shop=<publicId>`, 5-босқич): `/s/<id>` саҳифасидаги «Дўконни очиш» тугмаси
/// Flutter веб-иловани шу параметр билан очади. Ишга тушишда ушланади ([captureFromUrl]) ва бош саҳифа очилгач
/// (логиндан кейин ҳам) бир марта ишлатилади ([openIfAny]). Блокланган/номаълум — «вақтинча мавжуд эмас».
///
/// Android App Links (2026-10-25): ўша `/s/<id>` ҳаволаси ўрнатилган иловани тўғридан-тўғри очади
/// ([listenAppLinks] → [captureAppLink]) ва шу навбатнинг ўзига тушади — алоҳида механизм йўқ.
class PendingShopLink {
  PendingShopLink._();

  static final _idRe = RegExp(r'^[A-Za-z0-9]{10}$');
  static String? _id;

  /// `/s/` ҳаволаси келди, лекин ID нотўғри — бош саҳифада «вақтинча мавжуд эмас» (веб `/s/` саҳифаси ҳам
  /// шундай ҳолда «топилмади» кўрсатади).
  static bool _broken = false;

  /// Статистика манбаи: QR-коддан (`qr`) ёки улашилган ҳаволадан (`link`).
  static String _source = 'link';

  /// App Link ҳаволаси шу хост учун (manifest intent-filter ва `web/.well-known/assetlinks.json` билан бир хил).
  static const appLinkHost = 'master-taxi-gurlan.web.app';

  /// Илова ишлаб турганда янги ҳавола келди — бош саҳифа тинглайди ва [openIfAny] чақиради.
  static final ValueNotifier<int> arrivals = ValueNotifier<int>(0);

  /// [uri] — тест учун; бўлмаса вебда `Uri.base`. Мобил иловада бу ерда ҳеч нарса қилмайди (у ерда [captureAppLink]).
  static void captureFromUrl([Uri? uri]) {
    if (uri == null && !kIsWeb) return;
    final q = (uri ?? Uri.base).queryParameters;
    final id = q['shop']?.trim() ?? '';
    if (_idRe.hasMatch(id)) {
      _id = id;
      _broken = false;
      _source = q['src'] == 'qr' ? 'qr' : 'link';
    }
  }

  /// `https://master-taxi-gurlan.web.app/s/<publicId>[?src=qr]`. `null` — бу дўкон ҳаволаси эмас (эътиборсиз).
  /// `id == null` — `/s/` ҳаволаси, лекин ID нотўғри ёки ортиқча йўл бор. Манба: `src=qr` → `qr`, бошқаси → `link`
  /// (сервер `shopPage` билан бир хил).
  static ({String? id, String source})? parseAppLink(Uri uri) {
    if (uri.scheme != 'https' || uri.host != appLinkHost) return null;
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.isEmpty || seg.first != 's') return null;
    final id = seg.length == 2 && _idRe.hasMatch(seg[1]) ? seg[1] : null;
    return (id: id, source: uri.queryParameters['src'] == 'qr' ? 'qr' : 'link');
  }

  /// App Link'ни навбатга қўяди ва [arrivals]ни оширади. `false` — бизнинг ҳавола эмас.
  static bool captureAppLink(Uri uri) {
    final link = parseAppLink(uri);
    if (link == null) return false;
    _id = link.id;
    _broken = link.id == null;
    _source = link.source;
    debugPrint('[PendingShopLink] app link: ${link.id == null ? 'invalid' : 'ok'} src=${link.source}');
    arrivals.value++;
    return true;
  }

  /// Android: `AppLinks().uriLinkStream` (бошланғич ҳавола ҳам шу оқимда келади) — илова умри давомида.
  static StreamSubscription<Uri> listenAppLinks(Stream<Uri> links) => links.listen(
        captureAppLink,
        onError: (Object e) => debugPrint('[PendingShopLink] app link stream: $e'),
      );

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
    final broken = _broken;
    _broken = false;
    final id = take();
    if (id == null) {
      if (broken && context.mounted) _showUnavailable(context);
      return;
    }
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
      _showUnavailable(context);
      return;
    }
    final screen = TvShopPublicScreen(ownerPhone: target.ownerPhone, businessId: target.businessId, source: _source);
    if (push != null) return push(screen);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  static void _showUnavailable(BuildContext context) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('shop_unavailable'))));
}
