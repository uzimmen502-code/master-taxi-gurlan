import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/service_config_holder.dart';
import '../../business_map/domain/business.dart';
import '../../business_map/screens/business_products_screen.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../wholesale/models/wholesale_product.dart';
import '../../wholesale/screens/wholesale_market_screen.dart';
import '../widgets/shop_name_dialog.dart';

/// Асосий дўкон — эганинг ўз маҳсулотлари бир жойда, икки бўлимда: Аҳоли бозори
/// (`ads`) ва Улгуржи (`wholesale_*`). Каталогда ҳар маҳсулот РАСМ ва ВИДЕО билан
/// (видео AVAGram лентасига ҳам тушади, лекин AVAGram алоҳида бўлим эмас). Номи
/// `tv_shops/{телефон}.name`да (ўзгартириш мумкин).
///
/// Янги маълумот модели йўқ: рўйхатлар мавжуд омборлардан, мавжуд вижетлар
/// билан. Қўшимча дўконлар — Бизнес харитаси объектлари ([MyShopScreen]).
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

  /// Ном ўқиб бўлингач (ёки ўқилмади) — Аҳоли каталоги шундан кейин қурилади: маҳсулотга
  /// дўкон номи ёзилади ([Business.ownShop]).
  bool _nameLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialSegment.clamp(0, 1),
    );
    _loadName();
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
      if (mounted) {
        setState(() {
          _name = name;
          _nameLoaded = true;
        });
      }
    } catch (e) {
      // Ном ҳамроҳ маълумот: ўқилмаса сарлавҳа «Менинг дўконим» бўлиб қолади, каталог барибир очилади.
      debugPrint('[MainShop] loadName failed: $e');
      if (mounted) setState(() => _nameLoaded = true);
    }
  }

  /// Аҳоли бозори каталоги: ЯГОНА омбор — `tv_shop_items` (эганинг `businessId`сиз маҳсулотлари), расм ва видео
  /// билан; қўшимча дўконлар билан бир хил экран ([BusinessProductsScreen]).
  Widget _retail(BuildContext context) {
    final custom = widget.retailView;
    if (custom != null) return custom(context);
    if (!_nameLoaded) return const Center(child: CircularProgressIndicator());
    return BusinessProductsScreen(
      business: Business.ownShop(
        ownerId: widget.phone,
        name: _name.isNotEmpty ? _name : context.tr('my_shop_title'),
        districtId: ServiceConfigHolder.districtId.trim(),
      ),
      embedded: true,
      openFormOnStart: widget.openAddOnStart && widget.initialSegment == 0,
    );
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
        title: Text(_name.isNotEmpty ? _name : context.tr('my_shop_title')),
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
          _retail(context),
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
