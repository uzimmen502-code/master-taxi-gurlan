import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../business_map/data/business_repository.dart';
import '../../business_map/domain/business.dart';
import '../../business_map/domain/business_category.dart';
import '../../business_map/screens/business_form_screen.dart';
import '../../business_map/screens/business_products_screen.dart';
import '../my_shop_presence.dart';
import 'main_shop_screen.dart';

/// «Менинг дўконим» — эганинг ВАЖДА БИТТА эмас, бир нечта дўкони:
///  · «Асосий дўкон» — Аҳоли, Улгуржи ва AVAGram маҳсулотлари ([MainShopScreen]);
///  · «Бошқа дўконлар» — Бизнес харитасидаги чакана/улгуржи объектлар: ҳар
///    бирининг ўз номи ва ўз маҳсулотлари (сони чекланмаган), мавжуд
///    [BusinessProductsScreen] билан.
/// «Янги дўкон» — мавжуд [BusinessFormScreen] (ном, жой, телефон).
class MyShopScreen extends StatefulWidget {
  const MyShopScreen({
    super.key,
    required this.phone,
    this.initialSegment = 0,
    this.canCreateShop = true,
    @visibleForTesting this.businesses,
    @visibleForTesting this.loadMainName,
  });

  /// Каноник телефон (`canonicalPhoneId`) — чақирувчи 9+ рақам эканини текширади.
  final String phone;

  /// Асосий дўкон қайси сегментдан очилади (0 — Аҳоли, 1 — Улгуржи).
  final int initialSegment;

  /// «Янги дўкон» тугмаси: Бизнес харитаси модули очиқ бўлса.
  final bool canCreateShop;

  /// Тест учун: ҳақиқий Firestore обунаси ва ном ўқиш ўрнига.
  final Stream<List<Business>>? businesses;
  final Future<String> Function()? loadMainName;

  @override
  State<MyShopScreen> createState() => _MyShopScreenState();
}

class _MyShopScreenState extends State<MyShopScreen> {
  late final Stream<List<Business>> _stream =
      widget.businesses ?? BusinessRepository().watchMine(widget.phone);
  late Future<String> _nameFuture = _loadName();

  Future<String> _loadName() async {
    try {
      return await (widget.loadMainName ?? () => loadMainShopName(widget.phone))();
    } catch (e) {
      debugPrint('[MyShop] main name failed: $e');
      return '';
    }
  }

  Future<void> _openMain() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => MainShopScreen(
        phone: widget.phone,
        initialSegment: widget.initialSegment,
      ),
    ));
    // Номи ўзгарган бўлиши мумкин.
    if (mounted) setState(() => _nameFuture = _loadName());
  }

  Future<void> _openProducts(Business b) => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => BusinessProductsScreen(business: b)),
      );

  Future<void> _openForm([Business? b]) => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => BusinessFormScreen(
            existing: b,
            initialCategory: BusinessCategory.retail,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('my_shop_title'))),
      body: StreamBuilder<List<Business>>(
        stream: _stream,
        builder: (context, snap) {
          // Хато/юкланмоқда — асосий дўкон барибир кўринади (унинг маълумоти бошқа
          // манбадан); қўшимча дўконлар рўйхати фақат ўқилса чиқади.
          final shops = (snap.data ?? const <Business>[])
              .where(MyShopPresence.isShopCategory)
              .toList(growable: false);
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              FutureBuilder<String>(
                future: _nameFuture,
                builder: (context, nameSnap) {
                  final name = (nameSnap.data ?? '').trim();
                  return _ShopCard(
                    icon: Icons.storefront_rounded,
                    title: name.isNotEmpty ? name : context.tr('my_shop_main_title'),
                    subtitle: context.tr('my_shop_main_sub'),
                    onTap: _openMain,
                  );
                },
              ),
              if (shops.isNotEmpty || snap.hasError) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                  child: Text(
                    context.tr('my_shop_other_title'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                if (snap.hasError)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(context.tr('bizmap_err_generic')),
                  ),
                for (final b in shops)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ShopCard(
                      icon: b.category.icon,
                      title: b.name,
                      subtitle: [
                        context.tr(b.category.labelKey),
                        if (b.address.isNotEmpty) b.address,
                      ].join(' · '),
                      onTap: () => _openProducts(b),
                      trailing: IconButton(
                        tooltip: context.tr('my_shop_rename'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openForm(b),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: widget.canCreateShop
          ? FloatingActionButton.extended(
              onPressed: _openForm,
              backgroundColor: AppColors.primaryDark,
              foregroundColor: AppColors.onPrimary,
              icon: const Icon(Icons.add_rounded),
              label: Text(context.tr('my_shop_new_shop')),
            )
          : null,
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        minVerticalPadding: 12,
        leading: Icon(icon, color: AppColors.primaryDark),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
