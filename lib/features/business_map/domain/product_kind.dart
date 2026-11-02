import 'business.dart';
import 'business_category.dart';
import 'business_type_profile.dart';

/// Дўкон тоифаси — «Менинг онлайн дўконим»даги дўконлар («Савдо ва дўконлар»; эски чакана/улгуржи ҳам шу
/// турга ўгирилади — [BusinessCategory.legacyWires]). Ягона манба (`MyShopPresence.isShopCategory` ҳам шуни ишлатади).
bool isShopCategory(BusinessCategory c) => c == BusinessCategory.retail;

/// Дўконда (асосий дўкон ёки чакана/улгуржи) фақат маҳсулот: «Хизмат» танлови йўқ (эга, 2026-10-26: «дўкон ичида
/// қанақа хизмат бўлиши мумкин»). Бошқа объектларда (сартарош, ўқув маркази …) танлов қолади.
bool sellsOnlyProducts(Business b) => b.isOwnShop || isShopCategory(b.category);

/// Объект маҳсулоти учун бошланғич тур: `service` (хизмат) ёки `product` (маҳсулот). Эга формада ўзгартира олади.
/// Ягона манба — [BusinessTypeProfile] (тур + аниқроқ тур; масалан «Автосервис» — хизмат, «Автомобиль эҳтиёт
/// қисмлари» — маҳсулот). [subtype] берилмаса ёки тан олинмаса — тур бошланғичи.
String defaultProductKind(BusinessCategory c, {String subtype = ''}) =>
    BusinessTypeProfile.of(c, subtype: subtype).defaultKind.wire;

/// Нарх майдони: бўш — 0 (нарх кўрсатилмайди); бўшлиқ ва вергул ҳисобга олинмайди; манфий, ҳарфли ёки 9 хонадан узун — `null`.
/// Бутун сўм (8-банд: пул float эмас).
int? parseProductPrice(String raw) {
  final s = raw.replaceAll(RegExp(r'[\s,]'), '');
  if (s.isEmpty) return 0;
  if (!RegExp(r'^\d{1,9}$').hasMatch(s)) return null;
  return int.parse(s);
}
