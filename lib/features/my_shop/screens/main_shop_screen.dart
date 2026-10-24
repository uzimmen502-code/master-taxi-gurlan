import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../ads/screens/create_ad_screen.dart';
import '../../ads/screens/my_ads_screen.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../wholesale/models/wholesale_product.dart';
import '../../wholesale/screens/wholesale_market_screen.dart';
import '../widgets/shop_name_dialog.dart';

/// Асосий дўкон — эганинг ўз маҳсулотлари бир жойда: Аҳоли бозори ва Улгуржи.
/// Номи `tv_shops/{телефон}.name`да (ўзгартириш мумкин).
///
/// Янги маълумот модели йўқ: рўйхатлар мавжуд `ads` ва `wholesale_*`дан,
/// мавжуд вижетлар билан. Қўшимча дўконлар — Бизнес харитаси объектлари
/// ([MyShopScreen]).
class MainShopScreen extends StatefulWidget {
  const MainShopScreen({
    super.key,
    required this.phone,
    this.initialSegment = 0,
    this.openAddOnStart = false,
    @visibleForTesting this.loadName,
    @visibleForTesting this.saveName,
    @visibleForTesting this.retailView,
    @visibleForTesting this.wholesaleView,
  });

  /// Каноник телефон (`canonicalPhoneId`) — чақирувчи 9+ рақам эканини текширади.
  final String phone;

  /// 0 — Аҳоли бозори, 1 — Улгуржи.
  final int initialSegment;

  /// Биринчи киришда («Онлайн Дўкон очиш» → Аҳоли бозори): янги маҳсулот
  /// формаси дарҳол очилади. Юборилгач эга шу экранга қайтади — рўйхат ва
  /// «Янги маҳсулот» тугмаси турибди, яъни яна қўшиш мумкин (аввал форма
  /// ёпилгач бош саҳифага тушиб қолинар эди).
  final bool openAddOnStart;

  /// Тест учун: ном ўқиш/сақлаш ва ҳақиқий (Firestore'га уланадиган) сегментлар ўрнига.
  final Future<String> Function()? loadName;
  final Future<void> Function(String name)? saveName;
  final WidgetBuilder? retailView;
  final WidgetBuilder? wholesaleView;

  @override
  State<MainShopScreen> createState() => _MainShopScreenState();
}

class _MainShopScreenState extends State<MainShopScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  String _name = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialSegment.clamp(0, 1),
    );
    _loadName();
    if (widget.openAddOnStart && widget.initialSegment == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openRetailAddForm(context);
      });
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadName() async {
    try {
      final load = widget.loadName ?? () => loadMainShopName(widget.phone);
      final name = await load();
      if (mounted) setState(() => _name = name);
    } catch (e) {
      // Ном ҳамроҳ маълумот: ўқилмаса сарлавҳа «Асосий дўкон» бўлиб қолади.
      debugPrint('[MainShop] loadName failed: $e');
    }
  }

  Future<void> _rename() async {
    final saved = await showShopNameDialog(
      context,
      initial: _name,
      save: widget.saveName ?? (n) => saveMainShopName(widget.phone, n),
    );
    if (saved != null && mounted) setState(() => _name = saved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_name.isNotEmpty ? _name : context.tr('my_shop_main_title')),
        actions: [
          IconButton(
            tooltip: context.tr('my_shop_rename'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: _rename,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AvaLight.ink,
          unselectedLabelColor: AppColors.sectionMuted,
          indicatorColor: AvaLight.ink,
          tabs: [
            Tab(text: context.tr('tv_shop_to_market')),
            Tab(text: context.tr('home_module_wholesale')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        // Ичида ҳам табли рўйхат бор (Фаол · Текширувда · Яширилган): ён томонга
        // суриш иккита жестни тўқнаштирар эди — сегмент фақат босиш билан алмашади.
        physics: const NeverScrollableScrollPhysics(),
        children: [
          widget.retailView?.call(context) ?? _RetailShopView(uid: widget.phone),
          widget.wholesaleView?.call(context) ??
              WholesaleSellerArea(
                phone: widget.phone,
                market: WholesaleProduct.marketWholesale,
              ),
        ],
      ),
    );
  }
}

/// Асосий дўкон номи (`tv_shops/{телефон}.name`); ҳужжат ёки ном йўқ бўлса — бўш.
Future<String> loadMainShopName(String phone) async {
  final shop = await TvShopRepository().fetchShop(phone);
  return shop?.name.trim() ?? '';
}

/// Номни сақлайди ([TvShopRepository.saveName]: ҳужжат бўлмаса яратади).
Future<void> saveMainShopName(String phone, String name) =>
    TvShopRepository().saveName(ownerPhone: phone, name: name);

/// Аҳоли бозорига янги маҳсулот формаси (ягона кириш нуқтаси).
Future<void> openRetailAddForm(BuildContext context) => Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const CreateAdScreen()),
    );

/// Аҳоли бозори сегменти: ўз эълонлари (уч ҳолат) + пастда «Янги маҳсулот».
class _RetailShopView extends StatelessWidget {
  const _RetailShopView({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: TabBar(
                labelColor: AvaLight.ink,
                unselectedLabelColor: AppColors.sectionMuted,
                indicatorColor: AvaLight.ink,
                tabs: [
                  Tab(text: context.tr('jobs_status_active')),
                  Tab(text: context.tr('jobs_status_pending')),
                  Tab(text: context.tr('wholesale_status_inactive')),
                ],
              ),
            ),
            Expanded(child: MyAdsTabView(uid: uid)),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => openRetailAddForm(context),
              icon: const Icon(Icons.add),
              label: Text(context.tr('wholesale_new_product')),
            ),
          ),
        ),
      ),
    );
  }
}
