// «Бозорлар» 2b (эга 2026-11-15): сотувчи кўрадиган эълон ҳолати — олдиндан модерация ва 30 кунлик муддат.
//
// Сервер шартномаси: `functions/market_moderation.js` (2a). `tv_shop_items.status`:
//   active | pending | rejected | expired | deleted | blocked
// Бу ерда ФАҚАТ кўриниш (44-банд): ҳолатни сервер ўзгартиради, клиент статус ёзмайди (rules: эга фақат `deleted`).
// Эски ҳужжат (`expiresAt`/`rejectReason` йўқ) — аввалгидек: нишонсиз, «N кун қолди»сиз.

import '../models/tv_shop.dart';
import 'price_unit.dart';

/// Сотувчи рўйхатидаги нишон.
enum ListingBadge { none, pending, rejected, expired, blocked }

class ListingStatusView {
  const ListingStatusView({
    required this.badge,
    this.reason = '',
    this.daysLeft,
  });

  final ListingBadge badge;

  /// Рад этиш сабаби (фақат [ListingBadge.rejected]); бўлмаса бўш.
  final String reason;

  /// Фаол эълон муддатигача қолган кунлар (юқорига яхлитланган, ≥ 1); муддат йўқ ёки ўтган — `null`.
  final int? daysLeft;

  /// «Янгилаш» тугмаси (сервер `renewMarketListing`: фақат `expired → pending`).
  bool get canRenew => badge == ListingBadge.expired;

  /// Нишон матни калити (`null` — нишон йўқ). `blocked` — мавжуд `bizprod_status_blocked` калити.
  String? get labelKey => switch (badge) {
        ListingBadge.none => null,
        ListingBadge.pending => 'listing_mod_status_pending',
        ListingBadge.rejected => 'listing_mod_status_rejected',
        ListingBadge.expired => 'listing_mod_status_expired',
        ListingBadge.blocked => 'bizprod_status_blocked',
      };
}

const _dayMs = 24 * 60 * 60 * 1000;

/// Эга таҳриридан кейин эълон текширувга тушадими (снекбар матни учун; ҳолатни сервер ўзгартиради).
///
/// Сервер (`planShopItemWrite`): контент майдони ўзгарса `active`/`expired` → `pending`. `pending` — текширувда
/// қолади (матн тўғри). `rejected`/`blocked` — сервер ўтказмайди → `false` (оддий «Сақланди»).
/// Формадаги контент майдонлари: `title`, `price`, `description`, `priceUnit` (`kind` — контент эмас).
bool editResubmitsForModeration(
  TvShopItem existing, {
  required String title,
  required int price,
  required String description,
  required PriceUnit priceUnit,
  // «Бозорлар»: бўлим/`attrs`/`imported` ҳам сервер CONTENT_FIELDS'ида (ўзгаргани — чақирувчи ҳисоблайди).
  bool marketChanged = false,
}) {
  const statuses = {'active', 'expired', 'pending'};
  if (!statuses.contains(existing.status)) return false;
  return marketChanged ||
      existing.title != title ||
      existing.price != price ||
      existing.description != description ||
      existing.priceUnit != priceUnit;
}

/// Ҳолатдан кўриниш (соф функция — тестланади). Номаълум ҳолат — нишонсиз (эски/келажак қиймати бузмасин).
ListingStatusView listingStatusView(TvShopItem item, {DateTime? now}) {
  switch (item.status) {
    case 'pending':
      return const ListingStatusView(badge: ListingBadge.pending);
    case 'rejected':
      return ListingStatusView(badge: ListingBadge.rejected, reason: item.rejectReason.trim());
    case 'expired':
      return const ListingStatusView(badge: ListingBadge.expired);
    case 'blocked':
      return const ListingStatusView(badge: ListingBadge.blocked);
    case 'active':
      return ListingStatusView(badge: ListingBadge.none, daysLeft: daysLeftUntil(item.expiresAt, now: now));
    default:
      return const ListingStatusView(badge: ListingBadge.none);
  }
}

/// [expiresAt]гача қолган кунлар: юқорига яхлитланади (23 соат → 1 кун); ўтган ёки йўқ — `null`.
int? daysLeftUntil(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return null;
  final ms = expiresAt.difference(now ?? DateTime.now()).inMilliseconds;
  if (ms <= 0) return null;
  return (ms + _dayMs - 1) ~/ _dayMs;
}
