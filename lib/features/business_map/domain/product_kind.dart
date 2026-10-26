import 'business.dart';
import 'business_category.dart';

/// Дўкон тоифаси (чакана / улгуржи) — «Менинг онлайн дўконим»даги дўконлар. Ягона манба
/// (`MyShopPresence.isShopCategory` ҳам шуни ишлатади).
bool isShopCategory(BusinessCategory c) => c == BusinessCategory.retail || c == BusinessCategory.wholesale;

/// Дўконда (асосий дўкон ёки чакана/улгуржи) фақат маҳсулот: «Хизмат» танлови йўқ (эга, 2026-10-26: «дўкон ичида
/// қанақа хизмат бўлиши мумкин»). Бошқа объектларда (сартарош, ўқув маркази …) танлов қолади.
bool sellsOnlyProducts(Business b) => b.isOwnShop || isShopCategory(b.category);

/// Объект маҳсулоти учун бошланғич тур: `service` (хизмат) ёки `product` (маҳсулот). Эга формада ўзгартира олади.
/// Хизмат кўрсатувчи турлар — хизмат; савдо/ишлаб чиқариш/овқат/авто/бошқа — маҳсулот.
String defaultProductKind(BusinessCategory c) {
  switch (c) {
    case BusinessCategory.personal:
    case BusinessCategory.homeServices:
    case BusinessCategory.health:
    case BusinessCategory.education:
    case BusinessCategory.leisure:
    case BusinessCategory.logistics:
    case BusinessCategory.professional:
    case BusinessCategory.itMedia:
      return 'service';
    case BusinessCategory.retail:
    case BusinessCategory.wholesale:
    case BusinessCategory.food:
    case BusinessCategory.auto:
    case BusinessCategory.manufacturing:
    case BusinessCategory.other:
      return 'product';
  }
}

/// Нарх майдони: бўш — 0 (нарх кўрсатилмайди); бўшлиқ ва вергул ҳисобга олинмайди; манфий, ҳарфли ёки 9 хонадан узун — `null`.
/// Бутун сўм (8-банд: пул float эмас).
int? parseProductPrice(String raw) {
  final s = raw.replaceAll(RegExp(r'[\s,]'), '');
  if (s.isEmpty) return 0;
  if (!RegExp(r'^\d{1,9}$').hasMatch(s)) return null;
  return int.parse(s);
}
