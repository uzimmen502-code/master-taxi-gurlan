import 'business.dart';
import 'business_category.dart';

/// Дўкон тоифаси — «Менинг онлайн дўконим»даги дўконлар («Савдо ва дўконлар»; эски чакана/улгуржи ҳам шу
/// турга ўгирилади — [BusinessCategory.legacyWires]). Ягона манба (`MyShopPresence.isShopCategory` ҳам шуни ишлатади).
bool isShopCategory(BusinessCategory c) => c == BusinessCategory.retail;

/// Дўконда (асосий дўкон ёки чакана/улгуржи) фақат маҳсулот: «Хизмат» танлови йўқ (эга, 2026-10-26: «дўкон ичида
/// қанақа хизмат бўлиши мумкин»). Бошқа объектларда (сартарош, ўқув маркази …) танлов қолади.
bool sellsOnlyProducts(Business b) => b.isOwnShop || isShopCategory(b.category);

/// Объект маҳсулоти учун бошланғич тур: `service` (хизмат) ёки `product` (маҳсулот). Эга формада ўзгартира олади.
/// Товар сотадиган/ишлаб чиқарадиган турлар — маҳсулот; қолганлари (хизмат кўрсатувчилар) — хизмат.
String defaultProductKind(BusinessCategory c) {
  switch (c) {
    case BusinessCategory.retail:
    case BusinessCategory.manufacturing:
    case BusinessCategory.agriculture:
    case BusinessCategory.food:
    case BusinessCategory.auto:
    case BusinessCategory.foreignTrade:
    case BusinessCategory.fashion:
    case BusinessCategory.other:
      return 'product';
    case BusinessCategory.logistics:
    case BusinessCategory.construction:
    case BusinessCategory.realEstate:
    case BusinessCategory.personal:
    case BusinessCategory.education:
    case BusinessCategory.health:
    case BusinessCategory.it:
    case BusinessCategory.marketing:
    case BusinessCategory.finance:
    case BusinessCategory.professional:
    case BusinessCategory.tourism:
    case BusinessCategory.sport:
    case BusinessCategory.creative:
    case BusinessCategory.family:
    case BusinessCategory.animals:
    case BusinessCategory.energy:
    case BusinessCategory.rental:
    case BusinessCategory.agency:
    case BusinessCategory.ecology:
    case BusinessCategory.security:
    case BusinessCategory.businessSupport:
    case BusinessCategory.social:
      return 'service';
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
