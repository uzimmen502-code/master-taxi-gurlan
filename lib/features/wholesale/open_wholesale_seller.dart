import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../home/home_market_nav.dart';
import 'models/wholesale_product.dart';
import 'models/wholesale_seller.dart';
import 'repositories/wholesale_sellers_repository.dart';
import 'screens/wholesale_market_screen.dart';
import 'screens/wholesale_product_form_screen.dart';

/// «＋» → «Улгуржи/Ишлаб чиқарувчи маҳсулотлари» (эга, 2026-11-13; аввал асосий
/// дўкондаги «Улгуржи» таби эди). Ичи — мавжуд [WholesaleSellerArea]: рўйхатдан
/// ўтиш, ҳолат, ўз маҳсулотлари, келган буюртмалар.
class WholesaleSellerScreen extends StatelessWidget {
  const WholesaleSellerScreen({super.key, required this.phone, @visibleForTesting this.body});

  /// Каноник телефон — чақирувчи текширади.
  final String phone;

  /// Тест учун: Firestore'га уланадиган [WholesaleSellerArea] ўрнига.
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('home_create_wholesale'))),
      body: body ??
          WholesaleSellerArea(phone: phone, market: WholesaleProduct.marketWholesale),
    );
  }
}

/// Тасдиқланган ва жўнатиш манзили бор сотувчи — маҳсулот формаси ДАРҲОЛ
/// (rules ҳам шуни талаб қилади: `wholesaleProductCreateOk`). Форма [WholesaleSellerScreen]
/// устида очилади: ёпилгач ёки сақлангач — ўз маҳсулотлари рўйхати, яна орқага —
/// чақирган экран. Бошқа ҳолатда (рўйхатдан ўтмаган, текширувда, рад этилган,
/// манзилсиз) — шу экраннинг ўзи (ўша ҳолат кўрсатилади).
///
/// Сотувчини ўқиб бўлмаса — форма эмас, экран (у ўз оқимини ўзи қайта уланади).
Future<void> openWholesaleSeller(
  BuildContext context, {
  required String phone,
  @visibleForTesting Future<WholesaleSeller?> Function(String phone)? loadSeller,
  @visibleForTesting WholesaleSellerScreen Function()? screenBuilder,
  @visibleForTesting Widget Function(WholesaleSeller seller)? formBuilder,
}) async {
  WholesaleSeller? seller;
  try {
    seller = await (loadSeller ?? WholesaleSellersRepository().fetchByPhone)(phone);
  } catch (e) {
    debugPrint('[WholesaleSeller] load failed: $e');
  }
  if (!context.mounted) return;
  final screen = screenBuilder?.call() ?? WholesaleSellerScreen(phone: phone);
  final s = seller;
  if (s != null && s.isApproved && s.hasShipFrom) {
    await pushDetailOverMarket(
      context,
      market: screen,
      openDetail: () => Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) =>
            formBuilder?.call(s) ??
            WholesaleProductFormScreen(seller: s, market: WholesaleProduct.marketWholesale),
      )),
    );
    return;
  }
  await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));
}
