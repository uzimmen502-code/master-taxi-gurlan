import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/service_config_holder.dart';
import '../../business_map/domain/business.dart';
import '../../business_map/screens/business_products_screen.dart';
import '../../../models/map_picker_result.dart';
import '../../map_picker/screens/map_picker_screen.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../wholesale/models/wholesale_product.dart';
import '../../wholesale/screens/wholesale_market_screen.dart';
import '../widgets/shop_name_dialog.dart';

/// Асосий дўкон — эганинг ўз маҳсулотлари, икки бўлимда: Аралаш бозор ва Хитой
/// бозори (`wholesale_*`). «Улгуржи» таби олиб ташланди (эга, 2026-11-13) — у «＋» →
/// «Улгуржи/Ишлаб чиқарувчи маҳсулотлари» ([openWholesaleSeller]). Каталогда ҳар маҳсулот РАСМ ва ВИДЕО билан
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
    @visibleForTesting this.chinaView,
    @visibleForTesting this.loadShop,
    @visibleForTesting this.savePickup,
    @visibleForTesting this.pickPickup,
    @visibleForTesting this.loadPickup,
  });

  /// Тест учун: эганинг аниқ нуқтаси (private; бўлмаса — [TvShopRepository.fetchPickup]).
  final Future<ShopPickup?> Function()? loadPickup;

  /// Тест учун: дўкон ҳужжати (топшириш жойи; бўлмаса — [TvShopRepository.fetchShop]).
  final Future<TvShop?> Function()? loadShop;

  /// Тест учун: топшириш жойини сақлаш (бўлмаса — [TvShopRepository.savePickup]).
  final Future<void> Function(double lat, double lng, String address, bool showExact)? savePickup;

  /// Тест учун: харитада танлаш (бўлмаса — мавжуд [MapPickerScreen]).
  final Future<MapPickerResult?> Function(BuildContext context)? pickPickup;

  /// Каноник телефон (`canonicalPhoneId`) — чақирувчи 9+ рақам эканини текширади.
  final String phone;

  /// 0 — Аралаш бозор, 1 — Хитой бозори.
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
  final WidgetBuilder? chinaView;

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
    _loadPickup();
  }

  /// «Маҳсулотни топшириш жойи» (STAGE 11): `null` — ҳали ўқилмаган ёки ўқиб бўлмади (огоҳлантириш кўрсатилмайди).
  bool? _hasPickup;
  String _pickupAddress = '';
  bool _savingPickup = false;

  /// «Аниқ жойимни кўрсат» (оммавий `tv_shops.showExactLocation`; сукут — йўқ, тахминий ~500 м).
  bool _showExact = false;

  Future<void> _loadPickup() async {
    try {
      final shop = await (widget.loadShop?.call() ?? TvShopRepository().fetchShop(widget.phone));
      // Аниқ нуқта — эганинг private ҳужжати (эски оммавий майдонлар fallback). Тестда loadShop берилиб,
      // loadPickup берилмаса — Firestore'га борилмайди.
      final ShopPickup? pickup = widget.loadPickup != null
          ? await widget.loadPickup!()
          : (widget.loadShop != null ? null : await TvShopRepository().fetchPickup(widget.phone));
      if (!mounted) return;
      setState(() {
        _hasPickup = pickup != null || (shop?.hasPickup ?? false);
        _pickupAddress = pickup?.address ?? shop?.pickupAddress ?? '';
        _showExact = shop?.showExactLocation ?? false;
      });
    } catch (e) {
      debugPrint('[MainShop] loadPickup failed: $e');
    }
  }

  /// Харитада нуқта → манзил матни + «Аниқ жойимни кўрсат» → аниқ нуқта `tv_shops/{телефон}/private/pickup`,
  /// оммавий `tv_shops/{телефон}` да фақат тахминий `areaLat/areaLng` ([TvShopRepository.savePickup]).
  Future<void> _setPickup() async {
    if (_savingPickup) return;
    final custom = widget.pickPickup;
    final Future<MapPickerResult?> pending = custom != null
        ? custom(context)
        : Navigator.of(context).push<MapPickerResult>(
            MaterialPageRoute(builder: (_) => MapPickerScreen(title: context.tr('shop_pickup_title'))),
          );
    final r = await pending;
    if (!mounted || r == null) return;
    if (r.lat.abs() > 90 || r.lng.abs() > 180 || (r.lat == 0 && r.lng == 0)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('shop_pickup_err_point'))));
      return;
    }
    final answer = await _askAddress(r.label);
    if (!mounted || answer == null) return;
    final address = answer.address;
    setState(() => _savingPickup = true);
    try {
      final save = widget.savePickup ??
          (double lat, double lng, String a, bool exact) => TvShopRepository()
              .savePickup(ownerPhone: widget.phone, lat: lat, lng: lng, address: a, showExact: exact);
      await save(r.lat, r.lng, address, answer.showExact);
      if (!mounted) return;
      setState(() {
        _hasPickup = true;
        _pickupAddress = address;
        _showExact = answer.showExact;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('shop_pickup_saved'))));
    } catch (e) {
      debugPrint('[MainShop] savePickup failed: $e');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('shop_pickup_err_save'))));
      }
    } finally {
      if (mounted) setState(() => _savingPickup = false);
    }
  }

  Future<({String address, bool showExact})?> _askAddress(String initial) async {
    final ctrl = TextEditingController(text: initial.trim());
    var exact = _showExact;
    try {
      return await showDialog<({String address, bool showExact})>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(ctx.tr('shop_pickup_title')),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                key: const ValueKey('shop_pickup_address'),
                controller: ctrl,
                maxLength: 200,
                maxLines: 2,
                decoration: InputDecoration(labelText: ctx.tr('shop_pickup_address_label')),
              ),
              SwitchListTile(
                key: const ValueKey('shop_pickup_exact'),
                contentPadding: EdgeInsets.zero,
                value: exact,
                onChanged: (v) => setLocal(() => exact = v),
                title: Text(ctx.tr('shop_pickup_exact_toggle')),
                subtitle: Text(ctx.tr('shop_pickup_exact_hint'), style: const TextStyle(fontSize: 12)),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
              FilledButton(
                key: const ValueKey('shop_pickup_save'),
                onPressed: () {
                  final v = ctrl.text.trim();
                  if (v.length >= 3) Navigator.pop(ctx, (address: v, showExact: exact));
                },
                child: Text(ctx.tr('save')),
              ),
            ],
          ),
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Widget _pickupBanner(BuildContext context) {
    final c = context.ava;
    final missing = _hasPickup == false;
    return Material(
      color: missing ? c.warnSoft : c.surface2,
      child: InkWell(
        key: const ValueKey('shop_pickup_banner'),
        onTap: _setPickup,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AvaSpace.screen, vertical: 10),
          child: Row(children: [
            Icon(Icons.place_outlined, size: 20, color: missing ? c.warn : c.ink2),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                missing
                    ? context.tr('shop_pickup_missing')
                    : '${context.tr('shop_pickup_title')}: $_pickupAddress',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: missing ? c.warn : c.ink),
              ),
            ),
            const SizedBox(width: 6),
            _savingPickup
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr(missing ? 'shop_pickup_set' : 'biz_order_address_change'),
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.brandText)),
          ]),
        ),
      ),
    );
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
          // Қисқа номлар («бозор» сўзисиз, эга 2026-11-01).
          tabs: [
            Tab(text: context.tr('my_shop_tab_aralash')),
            Tab(text: context.tr('my_shop_tab_china')),
          ],
        ),
      ),
      body: Column(
        children: [
          // «Маҳсулотни топшириш жойи» — мажбурий (STAGE 11): белгиланмаса AVA курьери буюртмаси ишламайди.
          if (_hasPickup != null) _pickupBanner(context),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              // Ичида ҳам табли рўйхат бор (Фаол · Текширувда · Яширилган): ён томонга
              // суриш иккита жестни тўқнаштирар эди — сегмент фақат босиш билан алмашади.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _retail(context),
                // Хитой маҳсулотини қўшиш (бозор экранидаги «Сотувчи» таби ўрнига, эга 2026-11-01).
                widget.chinaView?.call(context) ??
                    WholesaleSellerArea(
                      phone: widget.phone,
                      market: WholesaleProduct.marketChina,
                    ),
              ],
            ),
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
