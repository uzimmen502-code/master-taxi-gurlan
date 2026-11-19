import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/utils/formatters.dart';
import '../../models/platform_product.dart';

/// Маҳсулот карточкаси белгиси (эга 2026-11-19/20): расмнинг ТЕПА ЧАП бурчагида БИТТА белги.
/// «−N%» (2026-11-20): жорий нарх майдонлари СЕРВЕРда чегирмали (харидор шуни тўлайди); асос promo.basePrice чизилади.
///
/// Устунлик: «−N%» → «Акция» → «Сўнгги доналар» → «Янги». Белгини фақат СЕРВЕР ёзган майдонлар беради
/// (`promo`, `firstActiveAt`, `stockLeft` — functions/product_promo.js; Rules мижозга ёпиқ). Мижоз фақат
/// кўрсатади: муддати ўтган «−N%»/«Акция» кўринмайди (`until <= now`). Сотувчи эркин матн ёза олмайди.
enum ProductBadgeKind { discount, promo, lastUnits, fresh }

/// «Янги» — фаоллашгандан 7 кун; «Сўнгги доналар» — қолдиқ 1..4 (0 = тугаган, белги эмас).
const Duration kProductNewWindow = Duration(days: 7);
const int kProductLowStockLimit = 5;

/// Сервер майдонларидан белги маълумоти (ҳужжатда йўқ — эски ҳужжат, белги йўқ).
@immutable
class ProductBadgeData {
  const ProductBadgeData({
    this.promoKind = '',
    this.percent = 0,
    this.basePrice = 0,
    this.until,
    this.firstActiveAt,
    this.stockLeft,
    this.stateStatus = '',
    this.stateReason = '',
    this.stateNote = '',
    this.statePercent = 0,
    this.requestKind = '',
    this.requestPercent = 0,
    this.requestUntil,
  });

  static const empty = ProductBadgeData();

  /// Тасдиқланган белги (`promo`): `discount` | `promo` | ''.
  final String promoKind;
  final int percent;

  /// Асос нарх (чегирмагача; сервер promo.basePrice). Карточкада чизилган ҳолда кўрсатилади.
  final int basePrice;
  final DateTime? until;

  /// Биринчи фаоллашув (сервер) — «Янги».
  final DateTime? firstActiveAt;

  /// Қолдиқ (wholesale, сервер ҳисоблайди); null — номаълум.
  final int? stockLeft;

  /// Сотувчи учун сўров ҳолати (`promoState`): pending | rejected | active | cleared.
  final String stateStatus;
  final String stateReason;
  final String stateNote;
  final int statePercent;

  /// Сотувчи юборган сўров (`promoRequest`) — форма учун.
  final String requestKind;
  final int requestPercent;
  final DateTime? requestUntil;

  bool get hasRequest => requestKind.isNotEmpty;

  factory ProductBadgeData.fromMap(Map<String, dynamic>? d) {
    if (d == null) return empty;
    final promo = d['promo'];
    final state = d['promoState'];
    final req = d['promoRequest'];
    final p = promo is Map ? promo : const {};
    final s = state is Map ? state : const {};
    final r = req is Map ? req : const {};
    final stock = d['stockLeft'];
    return ProductBadgeData(
      promoKind: _str(p['kind']),
      percent: _int(p['percent']),
      basePrice: _int(p['basePrice']),
      until: _date(p['until']),
      firstActiveAt: _date(d['firstActiveAt']),
      stockLeft: stock is int ? stock : null,
      stateStatus: _str(s['status']),
      stateReason: _str(s['reason']),
      stateNote: _str(s['note']),
      statePercent: _int(s['percent']),
      requestKind: _str(r['kind']),
      requestPercent: _int(r['percent']),
      requestUntil: _date(r['until']),
    );
  }

  /// AVA товари (platform_products, фақат админ ёзади): «−N%»/«Акция» — админ панелдан (сервер promo);
  /// қолдиқ = remaining (лимитсиз — йўқ), «Янги» — createdAt (админ ёзган вақт).
  factory ProductBadgeData.forPlatform(PlatformProduct p) => ProductBadgeData(
        promoKind: p.promoData.promoKind,
        percent: p.promoData.percent,
        basePrice: p.promoData.basePrice,
        until: p.promoData.until,
        stockLeft: p.isUnlimitedStock ? null : p.remaining,
        firstActiveAt: p.createdAt,
      );

  static String _str(Object? v) => v is String ? v : '';
  static int _int(Object? v) => v is int ? v : 0;
  static DateTime? _date(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  /// Амалдаги «−N%» (муддати ўтмаган) — асос нархни чизиш учун.
  bool activeDiscount(DateTime now) =>
      promoKind == 'discount' && percent >= 1 && basePrice > 0 && until != null && until!.isAfter(now);

  /// Карточкада чизиладиган асос нарх («10 000») ёки null (чегирма йўқ / муддати ўтган).
  String? strikePrice(DateTime now) => activeDiscount(now) ? formatPrice(basePrice) : null;
}

@immutable
class ProductBadge {
  const ProductBadge(this.kind, {this.percent = 0});
  final ProductBadgeKind kind;
  final int percent;
}

/// Битта белги (устунлик бўйича) ёки null. [now] — тест учун.
ProductBadge? resolveProductBadge(ProductBadgeData d, DateTime now) {
  final until = d.until;
  final promoLive = until != null && until.isAfter(now);
  if (promoLive && d.promoKind == 'discount' && d.percent >= 1 && d.percent <= 99) {
    return ProductBadge(ProductBadgeKind.discount, percent: d.percent);
  }
  if (promoLive && d.promoKind == 'promo') return const ProductBadge(ProductBadgeKind.promo);
  final left = d.stockLeft;
  if (left != null && left > 0 && left < kProductLowStockLimit) {
    return const ProductBadge(ProductBadgeKind.lastUnits);
  }
  final fa = d.firstActiveAt;
  if (fa != null && !fa.isAfter(now) && now.difference(fa) < kProductNewWindow) {
    return const ProductBadge(ProductBadgeKind.fresh);
  }
  return null;
}

/// Ранглар: chegirma/aksiya — қизил, янги — яшил, сўнгги доналар — тўқ сариқ (PROPOSED).
Color productBadgeColor(ProductBadgeKind k) => switch (k) {
      ProductBadgeKind.discount || ProductBadgeKind.promo => const Color(0xFFE53935),
      ProductBadgeKind.fresh => const Color(0xFF2E7D32),
      ProductBadgeKind.lastUnits => const Color(0xFFEF6C00),
    };

String productBadgeText(BuildContext context, ProductBadge b) => switch (b.kind) {
      ProductBadgeKind.discount => '−${b.percent}%',
      ProductBadgeKind.promo => context.tr('product_badge_promo'),
      ProductBadgeKind.lastUnits => context.tr('product_badge_last_units'),
      ProductBadgeKind.fresh => context.tr('product_badge_new'),
    };

/// Карточка расми устидаги белги (Stack ичида). Белги бўлмаса — ҳеч нарса чизилмайди.
/// [top] — бошқа тепа-чап белги бўлса (масалан «Меники») пастроққа суриш.
class ProductBadgeOverlay extends StatelessWidget {
  const ProductBadgeOverlay({super.key, required this.data, this.top = 6, this.left = 6, this.now});

  final ProductBadgeData data;
  final double top;
  final double left;

  /// Тест учун; null — `DateTime.now()`.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final b = resolveProductBadge(data, now ?? DateTime.now());
    if (b == null) return const SizedBox.shrink();
    return Positioned(
      top: top,
      left: left,
      child: IgnorePointer(
        child: Container(
          key: ValueKey('product_badge_${b.kind.name}'),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: productBadgeColor(b.kind), borderRadius: BorderRadius.circular(6)),
          child: Text(
            productBadgeText(context, b),
            maxLines: 1,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

/// Тафсилот экранида: амалдаги «−N%» бўлса эски нарх чизиқ билан (бўлмаса — ҳеч нарса).
class ProductOldPriceText extends StatelessWidget {
  const ProductOldPriceText({super.key, required this.data, required this.format, this.now});

  final ProductBadgeData data;
  final String Function(int price) format;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    if (!data.activeDiscount(now ?? DateTime.now())) return const SizedBox.shrink();
    return Text(
      format(data.basePrice),
      key: const ValueKey('product_old_price'),
      style: TextStyle(
        fontSize: 13,
        color: Colors.grey.shade600,
        decoration: TextDecoration.lineThrough,
      ),
    );
  }
}
