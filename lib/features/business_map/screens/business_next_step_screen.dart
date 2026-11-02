// «Кейинги қадам» / эга хаби — «Менинг бизнесим» занжирининг S1 слайси (эга, 2026-11-03).
//
// Битта экран икки ролда:
//  1) янги объект сақлангач (`justCreated: true`) — табрикдан кейин, дўкондан бошқа ҳамма тур;
//  2) «Менинг бизнесим» рўйхатида қатор босилганда — эга хаби (таҳрир шу ерга кўчди).
//
// Ҳамма матн ва қоида тур профилидан ([BusinessTypeProfile.forBusiness], ягона манба — 7-банд). Янги тизим ЭМАС:
// мавжуд «＋» занжирлари қайта ишлатилади — овқатланиш → [openBusinessMenuFlow] (ресторан бўлими), қолган турлар →
// [BusinessProductsScreen], ҳавола/QR → [showShopLinkSheet] (`getMyShopLink`), чатлар → «Хабарлар» ([NewsHubScreen]),
// тур кўприклари → мавжуд модул экранлари (модул ёпиқлиги [ServiceConfigHolder] да текширилади).
//
// Ўқиш: очилганда таклифлар сони учун БИТТА `fetchByBusiness` (листенер йўқ — 36-банд); каталогдан қайтгач қайта
// санаш. Объект ўзгариши (таҳрир) — чақирувчи берган [BusinessNextStepScreen.watch] оқимидан (рўйхат экрани билан
// бир хил сўров, Firestore SDK уни бирлаштиради).
//
// «Мижоз кўзи билан» ва «Ҳавола улашилди» белгилари — фақат шу қурилмада (SharedPreferences; эга учун қулайлик,
// сервер ҳолати эмас — PROPOSED).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/app_theme.dart';
import '../../ev_charging/screens/ev_charging_map_screen.dart';
import '../../my_shop/widgets/shop_link_sheet.dart';
import '../../profile/screens/news_hub_screen.dart';
import '../../realty/screens/add_realty_listing_screen.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../tv_market/screens/tv_shop_public_screen.dart';
import '../../yuk_local/screens/yuk_local_screen.dart';
import '../../business_orders/data/business_orders_repository.dart';
import '../../business_orders/domain/business_order.dart';
import '../../business_orders/screens/seller_business_orders_screen.dart';
import '../../business_orders/widgets/business_order_entry.dart' show businessAcceptsCourierOrders;
import '../business_food_flow.dart';
import '../data/business_repository.dart';
import '../domain/business.dart';
import '../domain/business_pin.dart';
import '../domain/business_subtypes.dart';
import '../domain/business_type_profile.dart';
import '../widgets/business_detail_sheet.dart';
import 'business_form_screen.dart';
import 'business_products_screen.dart';

/// Эга учун «кейинги қадам» экрани ва объект хаби.
class BusinessNextStepScreen extends StatefulWidget {
  const BusinessNextStepScreen({
    super.key,
    required this.business,
    this.justCreated = false,
    this.watch,
    this.linkedRestaurantIds = const {},
    TvShopRepository? shopRepository,
    BusinessRepository? businessRepository,
    @visibleForTesting this.loadOfferCount,
    this.openOffers,
    this.menuFlow,
    this.openEdit,
    @visibleForTesting this.openCustomerView,
    @visibleForTesting this.openShare,
    @visibleForTesting this.openChats,
    @visibleForTesting this.openBridge,
    @visibleForTesting this.loadOrdersInfo,
    @visibleForTesting this.openOrders,
  })  : _shopRepo = shopRepository,
        _bizRepo = businessRepository;

  final Business business;

  /// Янги объект сақланган заҳоти очилди (сарлавҳа «Кейинги қадам», пастда «Кейинроқ»). Бўлмаса — эга хаби.
  final bool justCreated;

  /// Объектнинг янги ҳолати (таҳрирдан кейин). `null` қиймат (ҳали/энди рўйхатда йўқ) эътиборсиз қолади.
  final Stream<Business?>? watch;

  /// Эганинг БОШҚА объектларига уланган ресторанлар — «Меню» занжирида таклиф қилинмайди.
  final Set<String> linkedRestaurantIds;

  final TvShopRepository? _shopRepo;
  final BusinessRepository? _bizRepo;

  /// Тест учун: таклифлар сонини ўқиш.
  final Future<int> Function(Business business)? loadOfferCount;

  /// Маҳсулот/хизмат каталоги ([BusinessProductsScreen]) ўрнига (рўйхат экрани ўз тест ҳукини узатади).
  final Future<void> Function(BuildContext context, Business business, bool openFormOnStart)? openOffers;

  /// «Меню» занжири ([openBusinessMenuFlow]) ўрнига (рўйхат экрани ўз тест ҳукини узатади).
  final Future<void> Function(BuildContext context, Business business, Set<String> linkedRestaurantIds)? menuFlow;

  /// Объект формаси ([BusinessFormScreen]) ўрнига (рўйхат экрани ўз формасини/тест ҳукини узатади).
  final Future<Object?> Function(BuildContext context, Business business)? openEdit;

  /// Тест учун: «Мижоз кўзи билан» ўрнига.
  final Future<void> Function(BuildContext context, Business business)? openCustomerView;

  /// Тест учун: ҳавола ва QR варағи ўрнига.
  final Future<void> Function(BuildContext context, Business business)? openShare;

  /// Тест учун: «Хабарлар» → «Чатлар» ўрнига.
  final Future<void> Function(BuildContext context)? openChats;

  /// Тест учун: тур кўприги (уй-жой эълони / юк ташувчи / зарядлаш станцияси) ўрнига.
  final Future<void> Function(BuildContext context, BusinessModuleBridge bridge)? openBridge;

  /// Тест учун: «Буюртмалар» қатори маълумоти (`null` — қатор кўринмайди).
  final Future<BizSellerOrdersInfo?> Function(Business business)? loadOrdersInfo;

  /// Тест учун: сотувчи буюртмалари экрани ўрнига.
  final Future<void> Function(BuildContext context, Business business)? openOrders;

  @override
  State<BusinessNextStepScreen> createState() => _BusinessNextStepScreenState();
}

/// Эга хабидаги «Буюртмалар» қатори: [newCount] — сотувчи жавобини кутаётган (`placed`) буюртмалар.
typedef BizSellerOrdersInfo = ({int newCount, int total});

/// Қатор кўринадими: модул дарвозаси очиқ ва объект курьер етказишига мос, ёки буюртмалар аллақачон бор
/// (дарвоза кейин ёпилса ҳам эга ўз буюртмаларини кўра олсин). Онлайн объект ва асосий дўконда — йўқ.
Future<BizSellerOrdersInfo?> loadBizSellerOrdersInfo(Business b, {BusinessOrdersRepository? repository}) async {
  if (b.online || b.isOwnShop || b.id.isEmpty) return null;
  final repo = repository ?? BusinessOrdersRepository();
  final results = await Future.wait<Object?>([
    repo.access(businessId: b.id),
    repo.fetchSellerOrders(b.ownerId).then<List<BusinessOrder>?>((l) => l, onError: (Object e) {
      debugPrint('[BizNextStep] seller orders: $e');
      return null;
    }),
  ]);
  final access = results[0] as BusinessOrdersAccess;
  final orders = [for (final o in (results[1] as List<BusinessOrder>?) ?? const <BusinessOrder>[]) if (o.businessId == b.id) o];
  final open = access.allowed && businessAcceptsCourierOrders(b);
  if (!open && orders.isEmpty) return null;
  return (newCount: orders.where((o) => o.status == BusinessOrderStatus.placed).length, total: orders.length);
}

/// Пастки асосий тугма учун бажариладиган қадамлар.
enum _Step { offers, preview, share }

class _BusinessNextStepScreenState extends State<BusinessNextStepScreen> {
  late Business _b = widget.business;
  StreamSubscription<Business?>? _sub;

  /// Таклифлар сони; `null` — юкланмоқда ёки ўқиб бўлмади (у ҳолда «0 та» деб кўрсатилмайди).
  int? _count;

  bool _previewed = false;
  bool _shared = false;

  /// «Буюртмалар» қатори (AVA курьери билан маҳсулот буюртмалари); `null` — кўринмайди.
  BizSellerOrdersInfo? _orders;

  BusinessTypeProfile get _profile => BusinessTypeProfile.forBusiness(_b);

  /// Овқатланиш объекти ва менюга уланади (харитада, онлайн эмас) — «Меню» занжири. Онлайн овқатланиш объекти
  /// менюга уланмайди (сервер ҳам рад этади) — умумий каталог.
  bool get _menu => _profile.group == BusinessOfferGroup.menu && businessCanHaveMenu(_b);

  /// Каталог гуруҳи (онлайн овқатланиш → «маҳсулот ёки хизмат»).
  BusinessOfferGroup get _group =>
      _profile.group == BusinessOfferGroup.menu && !_menu ? BusinessOfferGroup.mixed : _profile.group;

  String get _offersTitleKey => _menu ? _profile.nextStepTitleKey : 'biz_next_${_group.name}_title';
  String get _offersSubKey => 'biz_next_${_group.name}_sub';
  String get _offersCtaKey => switch (_group) {
        BusinessOfferGroup.menu => 'bizmap_open_menu',
        BusinessOfferGroup.mixed => 'bizprod_add',
        _ => 'biz_next_${_group.name}_cta',
      };

  bool get _offersDone => _menu ? _b.hasRestaurant : (_count ?? 0) > 0;

  String get _prefPreview => 'biz_next_preview_${_b.id}';
  String get _prefShare => 'biz_next_share_${_b.id}';

  @override
  void initState() {
    super.initState();
    _sub = widget.watch?.listen((b) {
      if (b != null && mounted) setState(() => _b = b);
    }, onError: (Object e) => debugPrint('[BizNextStep] watch: $e'));
    unawaited(_loadMarks());
    unawaited(_loadCount());
    unawaited(_loadOrders());
  }

  /// Буюртмалар қатори — битта дарвоза чақируви + битта ўқиш (листенер йўқ, 36-қоида); хато — қатор йўқ.
  Future<void> _loadOrders() async {
    try {
      final b = _b;
      final info = await (widget.loadOrdersInfo?.call(b) ?? loadBizSellerOrdersInfo(b));
      if (mounted) setState(() => _orders = info);
    } catch (e) {
      debugPrint('[BizNextStep] orders ${_b.id}: $e');
    }
  }

  Future<void> _openOrders() async {
    final b = _b;
    final custom = widget.openOrders;
    if (custom != null) {
      await custom(context, b);
    } else {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => SellerBusinessOrdersScreen(sellerUid: b.ownerId, businessId: b.id),
      ));
    }
    if (mounted) await _loadOrders();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadMarks() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _previewed = p.getBool(_prefPreview) ?? false;
        _shared = p.getBool(_prefShare) ?? false;
      });
    } catch (e) {
      debugPrint('[BizNextStep] marks: $e');
    }
  }

  Future<void> _mark(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, true);
    } catch (e) {
      debugPrint('[BizNextStep] mark $key: $e');
    }
  }

  /// Таклифлар сони — битта ўқиш (меню объектида ўқилмайди: менюни ресторан бўлими юритади).
  Future<void> _loadCount() async {
    if (_menu) return;
    try {
      final b = _b;
      final n = await (widget.loadOfferCount?.call(b) ??
          (widget._shopRepo ?? TvShopRepository())
              .fetchByBusiness(b.id, ownerPhone: b.ownerId, onlyActive: false)
              .then((l) => l.length));
      if (!mounted) return;
      setState(() => _count = n);
    } catch (e) {
      // Ўқиб бўлмади — сон кўрсатилмайди, қадам «бажарилмаган» қолади (эга каталогни очиб кўра олади).
      debugPrint('[BizNextStep] offers count ${_b.id}: $e');
    }
  }

  // ── Ҳаракатлар ───────────────────────────────────────────────────────────────────────────────────

  Future<void> _edit() async {
    final b = _b;
    await (widget.openEdit?.call(context, b) ??
        Navigator.of(context).push<Object?>(MaterialPageRoute(builder: (_) => BusinessFormScreen(existing: b))));
  }

  Future<void> _openOffers() async {
    final b = _b;
    if (_menu) {
      await (widget.menuFlow?.call(context, b, widget.linkedRestaurantIds) ??
          openBusinessMenuFlow(
            context,
            b,
            businessRepo: widget._bizRepo,
            linkedRestaurantIds: widget.linkedRestaurantIds,
          ));
      return;
    }
    // Бўш каталог — қўшиш формаси дарҳол очилади (эга бир босишда биринчи таклифни ёзади). Сони номаълум
    // (юкланмоқда/хато) бўлса — форма эмас, рўйхат.
    final openForm = _count == 0 && !_b.isBlocked;
    await (widget.openOffers?.call(context, b, openForm) ??
        Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => BusinessProductsScreen(business: b, repository: widget._shopRepo, openFormOnStart: openForm),
        )));
    if (mounted) await _loadCount();
  }

  /// Харидор кўрадиган юза: харитадаги объект — харита варағи; онлайн — онлайн дўкон саҳифаси (шу йўналиш).
  Future<void> _customerView() async {
    final b = _b;
    setState(() => _previewed = true);
    unawaited(_mark(_prefPreview));
    final custom = widget.openCustomerView;
    if (custom != null) return custom(context, b);
    if (!b.online) return BusinessDetailSheet.show(context, BusinessPin.fromBusiness(b));
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => TvShopPublicScreen(ownerPhone: b.ownerId, businessId: b.id),
    ));
  }

  Future<void> _share() async {
    final b = _b;
    setState(() => _shared = true);
    unawaited(_mark(_prefShare));
    final custom = widget.openShare;
    if (custom != null) return custom(context, b);
    await showShopLinkSheet(
      context,
      title: b.name,
      businessId: b.id,
      loadLink: widget._bizRepo?.getMyShopLink,
    );
  }

  Future<void> _chats() async {
    final custom = widget.openChats;
    if (custom != null) return custom(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const NewsHubScreen(initialTabIndex: 1)),
    );
  }

  /// Тур кўприги → мавжуд модул кириши (home_screen билан бир хил: модул ёпиқ бўлса — «тез кунда» хабари).
  Future<void> _bridge(BusinessModuleBridge bridge) async {
    final custom = widget.openBridge;
    if (custom != null) return custom(context, bridge);
    final (String? module, Widget screen) = switch (bridge) {
      BusinessModuleBridge.realtyListing => ('realty', const AddRealtyListingScreen()),
      BusinessModuleBridge.cargoLocal => ('yuk_local', const YukLocalScreen(openPublish: true)),
      // Зарядлаш станцияси — ПУЛЛИК қўшиш харита экранида (тариф варағи → форма), бош саҳифа ҳам шундай очади.
      BusinessModuleBridge.evStation => (null, const EvChargingMapScreen()),
    };
    if (module != null && !ServiceConfigHolder.isOpenable(module)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('home_coming_soon'))));
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));
  }

  // ── Кўриниш ──────────────────────────────────────────────────────────────────────────────────────

  /// Ҳисобга кирадиган 4 қадам (чатлар — маълумот, ҳисобга кирмайди).
  List<bool> get _progress => [true, _offersDone, _previewed, _shared];

  /// Пастки асосий тугма: биринчи бажарилмаган қадам; `null` — ҳаммаси тайёр.
  _Step? get _firstPending {
    if (!_offersDone) return _Step.offers;
    if (!_previewed) return _Step.preview;
    if (!_shared) return _Step.share;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ava = context.ava;
    final blocked = _b.isBlocked;
    final bridge = blocked ? null : _profile.moduleBridge;
    final noteKey = _profile.licenceNoteKey;
    final done = _progress.where((x) => x).length;
    final total = _progress.length;
    return Scaffold(
      backgroundColor: ava.bg,
      appBar: AppBar(
        title: Text(
          widget.justCreated ? context.tr('biz_next_title') : _b.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const ValueKey('biz_next_edit_action'),
            tooltip: context.tr('edit'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: _edit,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 12, AvaSpace.screen, 24),
        children: [
          _Hero(business: _b),
          if (blocked) ...[
            const SizedBox(height: 12),
            _Banner(
              key: const ValueKey('biz_next_blocked_banner'),
              icon: Icons.block_rounded,
              color: ava.danger,
              background: ava.dangerSoft,
              text: context.tr('bizprod_blocked_banner'),
            ),
          ],
          if (noteKey != null) ...[
            const SizedBox(height: 12),
            _Banner(
              key: const ValueKey('biz_next_licence_note'),
              icon: Icons.info_outline_rounded,
              color: ava.warn,
              background: ava.warnSoft,
              text: context.tr(noteKey),
            ),
          ],
          const SizedBox(height: 16),
          _ProgressHeader(done: done, total: total),
          const SizedBox(height: 12),
          _StepCard(
            key: const ValueKey('biz_next_step_placed'),
            index: 1,
            done: true,
            icon: _b.online ? Icons.public_rounded : Icons.place_rounded,
            title: context.tr(_b.online ? 'biz_next_step_online' : 'biz_next_step_placed'),
            subtitle: _b.online ? context.tr('bizmap_online_badge') : _b.address,
            ctaKey: const ValueKey('biz_next_cta_edit'),
            ctaLabel: context.tr('edit'),
            onCta: _edit,
          ),
          _StepCard(
            key: const ValueKey('biz_next_step_offers'),
            index: 2,
            done: _offersDone,
            icon: _menu ? Icons.restaurant_menu_rounded : Icons.inventory_2_outlined,
            title: context.tr(_offersTitleKey),
            subtitle: _offersSubtitle(context),
            ctaKey: const ValueKey('biz_next_cta_offers'),
            ctaLabel: context.tr(_offersDone ? 'biz_next_manage' : _offersCtaKey),
            // Блокда янги таклиф қўшиб бўлмайди (rules ҳам рад этади); борини кўриш мумкин.
            onCta: blocked && !_offersDone ? null : _openOffers,
          ),
          if (!blocked) ...[
            _StepCard(
              key: const ValueKey('biz_next_step_preview'),
              index: 3,
              done: _previewed,
              icon: Icons.visibility_outlined,
              title: context.tr('biz_next_step_preview'),
              subtitle: context.tr('biz_next_step_preview_sub'),
              ctaKey: const ValueKey('biz_next_cta_preview'),
              ctaLabel: context.tr('biz_customer_view'),
              onCta: _customerView,
            ),
            _StepCard(
              key: const ValueKey('biz_next_step_share'),
              index: 4,
              done: _shared,
              icon: Icons.qr_code_2_rounded,
              title: context.tr('biz_next_step_share'),
              subtitle: context.tr('biz_next_step_share_sub'),
              ctaKey: const ValueKey('biz_next_cta_share'),
              ctaLabel: context.tr('biz_link_qr'),
              onCta: _share,
            ),
          ],
          _StepCard(
            key: const ValueKey('biz_next_step_chats'),
            icon: Icons.chat_bubble_outline_rounded,
            title: context.tr('biz_next_step_chats'),
            ctaKey: const ValueKey('biz_next_cta_chats'),
            ctaLabel: context.tr('inbox_filter_chats'),
            onCta: _chats,
          ),
          if (_orders case final BizSellerOrdersInfo info)
            _StepCard(
              key: const ValueKey('biz_next_step_orders'),
              icon: Icons.receipt_long_rounded,
              title: context.tr('biz_order_seller_entry'),
              subtitle: info.newCount > 0
                  ? context.tr('biz_order_seller_entry_sub').replaceAll('{count}', '${info.newCount}')
                  : context.tr('biz_order_seller_entry_none'),
              ctaKey: const ValueKey('biz_next_cta_orders'),
              ctaLabel: info.newCount > 0 ? '${context.tr('biz_order_seller_open')} (${info.newCount})' : context.tr('biz_order_seller_open'),
              onCta: _openOrders,
            ),
          if (bridge != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(context.tr('biz_next_more_title'), style: AvaText.sectionTitle.copyWith(color: ava.ink)),
            ),
            _BridgeCard(
              key: ValueKey('biz_next_bridge_${bridge.name}'),
              icon: switch (bridge) {
                BusinessModuleBridge.realtyListing => Icons.home_work_outlined,
                BusinessModuleBridge.cargoLocal => Icons.local_shipping_outlined,
                BusinessModuleBridge.evStation => Icons.ev_station_outlined,
              },
              label: context.tr(bridge.ctaKey),
              onTap: () => _bridge(bridge),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _bottomBar(context),
    );
  }

  String _offersSubtitle(BuildContext context) {
    if (_menu) return context.tr(_b.hasRestaurant ? 'bizmap_menu_linked' : _offersSubKey);
    // Сони ўқилмаса — «0 та» деб алдамаймиз, оддий изоҳ.
    final n = _count;
    if (n != null && n > 0) return context.tr('biz_next_offer_count').replaceAll('{count}', '$n');
    return context.tr(_offersSubKey);
  }

  /// Пастки панел: «Кейинроқ» (фақат янги объектда) ва асосий тугма. Блокланган объектда асосий тугма йўқ.
  Widget? _bottomBar(BuildContext context) {
    final blocked = _b.isBlocked;
    if (blocked && !widget.justCreated) return null;
    final ava = context.ava;
    final showPrimary = !blocked;
    final (String label, VoidCallback action) = switch (_firstPending) {
      _Step.offers => (context.tr(_offersCtaKey), _openOffers),
      _Step.preview => (context.tr('biz_customer_view'), _customerView),
      _Step.share => (context.tr('biz_link_qr'), _share),
      null => (context.tr('biz_open_page'), _customerView),
    };
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 10, AvaSpace.screen, 10),
        decoration: BoxDecoration(color: ava.surface, border: Border(top: BorderSide(color: ava.line))),
        child: Row(
          children: [
            if (widget.justCreated)
              TextButton(
                key: const ValueKey('biz_next_later'),
                onPressed: () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(foregroundColor: ava.ink2, minimumSize: const Size(0, 48)),
                child: Text(context.tr('biz_next_later')),
              ),
            if (widget.justCreated && showPrimary) const SizedBox(width: 8),
            if (showPrimary)
              Expanded(
                child: FilledButton(
                  key: const ValueKey('biz_next_primary'),
                  onPressed: action,
                  style: FilledButton.styleFrom(
                    backgroundColor: ava.brand,
                    foregroundColor: ava.brandInk,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AvaRadius.card)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Бўлаклар ───────────────────────────────────────────────────────────────────────────────────────

/// Объект картаси: тур ранги доирада тур иконкаси, ном, тур · аниқроқ тур, ҳолат пилласи ва изоҳ.
class _Hero extends StatelessWidget {
  const _Hero({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    final ava = context.ava;
    final b = business;
    final c = b.category;
    final kind = [
      context.tr(c.labelKey),
      if (b.subtype.isNotEmpty) BusinessSubtypes.display(b.subtype, context.contentLang, category: c),
    ].join(' · ');
    final (String pill, IconData pillIcon, Color fg, Color bg) = b.isBlocked
        ? (context.tr('bizprod_status_blocked'), Icons.block_rounded, ava.danger, ava.dangerSoft)
        : b.online
            ? (context.tr('biz_next_pill_online'), Icons.public_rounded, ava.brandText, ava.brandSoft)
            : (context.tr('biz_next_pill_map'), Icons.place_rounded, ava.ok, ava.okSoft);
    return Container(
      key: const ValueKey('biz_next_hero'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ava.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ava.line),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.color.withValues(alpha: 0.10), ava.surface],
          stops: const [0, 0.7],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: c.color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: c.color.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Icon(c.icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.2, color: ava.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(kind, maxLines: 2, overflow: TextOverflow.ellipsis, style: AvaText.body.copyWith(color: ava.ink2)),
                    const SizedBox(height: 8),
                    Container(
                      key: const ValueKey('biz_next_pill'),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AvaRadius.chip)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(pillIcon, size: 14, color: fg),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              pill,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!b.isBlocked) ...[
            const SizedBox(height: 14),
            Text(
              context.tr(b.online ? 'biz_next_hero_online' : 'biz_next_hero_map'),
              style: AvaText.body.copyWith(color: ava.inkRow),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ava = context.ava;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('biz_next_progress').replaceAll('{done}', '$done').replaceAll('{total}', '$total'),
          key: const ValueKey('biz_next_progress'),
          style: AvaText.sectionTitle.copyWith(color: ava.ink),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AvaRadius.chip),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 8,
            backgroundColor: ava.surface2,
            valueColor: AlwaysStoppedAnimation<Color>(ava.brand),
          ),
        ),
      ],
    );
  }
}

/// Қадам картаси: чапда рақам ёки ✓, сарлавҳа, изоҳ, ўнгда тугма. [index] йўқ — маълумот қадами (иконка билан).
class _StepCard extends StatelessWidget {
  const _StepCard({
    super.key,
    this.index,
    this.done = false,
    required this.icon,
    required this.title,
    this.subtitle = '',
    required this.ctaKey,
    required this.ctaLabel,
    required this.onCta,
  });

  final int? index;
  final bool done;
  final IconData icon;
  final String title;
  final String subtitle;
  final Key ctaKey;
  final String ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final ava = context.ava;
    final Widget badge;
    if (done) {
      badge = Container(
        key: const ValueKey('biz_next_done'),
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: ava.ok, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
      );
    } else if (index != null) {
      badge = Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ava.brandSoft,
          shape: BoxShape.circle,
          border: Border.all(color: ava.brand, width: 1.5),
        ),
        child: Text('$index', style: TextStyle(fontWeight: FontWeight.w800, color: ava.brandText)),
      );
    } else {
      badge = Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: ava.surface2, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: ava.ink2),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(
          color: ava.surface,
          borderRadius: BorderRadius.circular(AvaRadius.card),
          border: Border.all(color: done ? ava.ok.withValues(alpha: 0.35) : ava.line),
        ),
        child: Row(
          children: [
            badge,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25, color: ava.ink),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: AvaText.caption.copyWith(color: ava.ink2)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Тугма матни узун бўлса (рус тили, тор экран) — 2 қаторгача, сарлавҳани сиқиб чиқармайди.
            if (onCta != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 136),
                child: done || index == null
                    ? TextButton(
                        key: ctaKey,
                        onPressed: onCta,
                        style: TextButton.styleFrom(
                          foregroundColor: ava.brandText,
                          minimumSize: const Size(0, AvaTap.minSize),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: Text(ctaLabel, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                      )
                    : FilledButton(
                        key: ctaKey,
                        onPressed: onCta,
                        style: FilledButton.styleFrom(
                          backgroundColor: ava.brand,
                          foregroundColor: ava.brandInk,
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          ctaLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.icon, required this.color, required this.background, required this.text});

  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AvaRadius.card)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AvaText.body.copyWith(color: context.ava.ink))),
        ],
      ),
    );
  }
}

class _BridgeCard extends StatelessWidget {
  const _BridgeCard({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ava = context.ava;
    return Material(
      color: ava.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AvaRadius.card),
        side: BorderSide(color: ava.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: ava.brandSoft, shape: BoxShape.circle),
          child: Icon(icon, color: ava.brandText),
        ),
        title: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: ava.ink)),
        trailing: Icon(Icons.chevron_right_rounded, color: ava.ink3),
      ),
    );
  }
}
