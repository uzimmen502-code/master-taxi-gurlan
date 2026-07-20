import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/offline_l10n.dart';
import '../../core/utils/formatters.dart';
import '../../services/notification_delivery.dart';
import '../../services/notification_service.dart';
import 'models/yuk_listing.dart';

/// Юк эълонлари: 6 соат олдин огоҳлантириш + ёпилганда хабар (локал).
class YukListingNotifier {
  YukListingNotifier._();

  static const warnBefore = Duration(hours: 6);

  static int _warnId(String listingId) =>
      'yuk_w_$listingId'.hashCode & 0x3FFFFFFF;

  static int _closedId(String listingId) =>
      'yuk_c_$listingId'.hashCode & 0x3FFFFFFF;

  static String _route(YukListing item) => '${item.from} → ${item.to}';

  static Future<void> cancelFor(String listingId) async {
    try {
      await NotificationService.instance.setup();
      await NotificationService.instance.cancelReminder(_warnId(listingId));
      await NotificationService.instance.cancelReminder(_closedId(listingId));
    } catch (e) {
      debugPrint('YukListingNotifier.cancelFor: $e');
    }
  }

  /// Фаол эълон учун огоҳлантиришларни (қайта) режалаштириш.
  static Future<void> scheduleFor(YukListing item) async {
    if (!item.isActive) {
      await cancelFor(item.id);
      return;
    }
    try {
      await NotificationService.instance.setup();
      await cancelFor(item.id);

      final route = _route(item);
      final warnTitle = await OfflineL10n.tr('yuk_notify_expire_soon_title');
      final warnBody = (await OfflineL10n.tr('yuk_notify_expire_soon_body'))
          .replaceAll('{route}', route);
      final closedTitle = await OfflineL10n.tr('yuk_notify_closed_title');
      final closedBody = (await OfflineL10n.tr('yuk_notify_closed_body'))
          .replaceAll('{route}', route);

      await NotificationService.instance.scheduleReminder(
        id: _warnId(item.id),
        title: warnTitle,
        body: warnBody,
        when: item.expiresAt.subtract(warnBefore),
      );
      await NotificationService.instance.scheduleReminder(
        id: _closedId(item.id),
        title: closedTitle,
        body: closedBody,
        when: item.expiresAt,
      );
    } catch (e) {
      debugPrint('YukListingNotifier.scheduleFor: $e');
    }
  }

  /// Эганинг барча актив эълонлари учун режани синхронлаш.
  static Future<void> syncOwner({
    required String ownerId,
    required List<YukListing> listings,
  }) async {
    if (ownerId.isEmpty) return;
    for (final item in listings) {
      if (item.ownerId != ownerId) continue;
      if (item.isActive) {
        await scheduleFor(item);
      } else {
        await cancelFor(item.id);
      }
    }
  }

  /// Илова очиқ вақтда автоёпилган эълонлар — фақат ўз эълони учун хабар.
  static Future<void> notifyJustClosed(List<YukListing> closed) async {
    if (closed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final me = phoneDigits(prefs.getString('user_phone') ?? '');
    for (final item in closed) {
      await cancelFor(item.id);
      if (me.length < 9 || item.ownerId != me) continue;
      final route = _route(item);
      final title = await OfflineL10n.tr('yuk_notify_closed_title');
      final body = (await OfflineL10n.tr('yuk_notify_closed_body'))
          .replaceAll('{route}', route);
      await NotificationDelivery.show(
        title: title,
        body: body,
        type: 'yuk_listing_closed',
        navigationData: const {'screen': 'yuk_birja'},
      );
    }
  }
}
