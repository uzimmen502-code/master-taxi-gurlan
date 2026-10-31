import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/product_detail_dark.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../core/widgets/edge_swipe_pager.dart';
import '../../../shared/widgets/wallet_topup_ui.dart' show walletPhoneId;
import '../../ads/widgets/ad_image_slider.dart';
import '../models/wholesale_product.dart';
import '../repositories/wholesale_orders_repository.dart';
import '../repositories/wholesale_products_repository.dart';
import '../repositories/wholesale_stock_repository.dart';
import '../widgets/wholesale_checkout_sheet.dart';
import 'wholesale_order_detail_screen.dart';
import '../services/wholesale_video_link.dart';
import '../utils/wholesale_labels.dart';
import '../utils/wholesale_similar.dart';
import '../widgets/wholesale_pack_chips.dart';
import '../widgets/wholesale_product_strip.dart';
import '../widgets/wholesale_tier_picker.dart';

/// Маҳсулот тафсилоти — қўнғироқ ҳамиша бор; буюртма дарвозаси очиқ
/// фойдаланувчига «Буюртма бериш» ҳам (4-босқич, [showWholesaleCheckoutSheet]:
/// нарх фақат сервер квотасидан, ҳамён ёки 3b карта).
///
/// Қора дизайн (эга қарори, 2026-10-17) ФАҚАТ шу тафсилот экранида.
/// Нарх поғонаси босиб танланади, миқдорга қараб сумма жонли ҳисобланади
/// (кўрсатиш учун; савват ва буюртма — D-ULG-1…9 дан кейин).
///
/// [catalog] бор бўлса, маълумот ТУГАГАНДАН кейин юқорига суриб кейинги,
/// тепада пастга суриб олдинги маҳсулотга ўтилади ([EdgeSwipePager]).
class WholesaleProductDetailScreen extends StatefulWidget {
  const WholesaleProductDetailScreen({
    super.key,
    required this.product,
    this.catalog = const [],
  });

  final WholesaleProduct product;

  /// Лентада юкланган товарлар — «ўхшаш», «сотувчининг бошқалари» ва
  /// свайп шундан олинади (қўшимча сўров йўқ). Бўш бўлса бу бўлимлар
  /// кўринмайди ва свайп йўқ.
  final List<WholesaleProduct> catalog;

  @override
  State<WholesaleProductDetailScreen> createState() =>
      _WholesaleProductDetailScreenState();
}

class _WholesaleProductDetailScreenState
    extends State<WholesaleProductDetailScreen> {
  late final List<WholesaleProduct> _swipeList = wholesaleSwipeList(
    widget.product,
    widget.catalog,
  );
  late int _index = _swipeList.indexWhere((p) => p.id == widget.product.id);

  /// Тугма билан ўтиш учун: пейджерни ташқаридан бошқарамиз (свайпга муқобил).
  late final PageController _pageCtrl = PageController(initialPage: _index);

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  /// -1 — олдинги, +1 — кейинги маҳсулот.
  void _step(int delta) {
    final target = (_index + delta).clamp(0, _swipeList.length - 1);
    if (target == _index) return;
    // Ҳаракатни камайтириш ёқилган бўлса — анимациясиз.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageCtrl.jumpToPage(target);
    } else {
      _pageCtrl.animateToPage(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _swipeList;
    // Битта маҳсулот бўлса суришнинг маъноси йўқ.
    if (list.length <= 1) {
      return WholesaleProductDetailView(
        product: widget.product,
        catalog: widget.catalog,
      );
    }
    // Фон қора мавзу рангида: судраганда саҳифа сал сурилади, орқада
    // бошқа ранг кўринмасин.
    return ColoredBox(
      color: PdDark.bg,
      child: Stack(
        children: [
          EdgeSwipePager(
            controller: _pageCtrl,
            itemCount: list.length,
            initialIndex: _index,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => WholesaleProductDetailView(
              // Калит бўлмаса саҳифа ҳолати (миқдор) қайта ишлатилиб кетади.
              key: ValueKey(list[i].id),
              product: list[i],
              catalog: widget.catalog,
              showNextHint: i < list.length - 1,
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + 2,
            right: 8,
            child: WholesaleSwipeNav(
              index: _index,
              count: list.length,
              onStep: _step,
            ),
          ),
        ],
      ),
    );
  }
}

/// «‹ 3 / 12 ›» — нечанчи маҳсулот эканини кўрсатади ва свайпга муқобил:
/// олдинги/кейинги маҳсулотга тугма билан ўтиш (WCAG 2.5.7, экран ўқувчи учун
/// ҳам). Чегарада тегишли тугма ўчиқ. Ҳар тугма 48×48 dp.
class WholesaleSwipeNav extends StatelessWidget {
  const WholesaleSwipeNav({
    super.key,
    required this.index,
    required this.count,
    required this.onStep,
  });

  final int index;
  final int count;

  /// -1 = олдинги, +1 = кейинги.
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('wholesale-swipe-prev'),
            tooltip: context.tr('wholesale_swipe_prev'),
            color: Colors.white,
            disabledColor: Colors.white38,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: index > 0 ? () => onStep(-1) : null,
          ),
          Text(
            '${index + 1} / $count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            key: const ValueKey('wholesale-swipe-next'),
            tooltip: context.tr('wholesale_swipe_next'),
            color: Colors.white,
            disabledColor: Colors.white38,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: index < count - 1 ? () => onStep(1) : null,
          ),
        ],
      ),
    );
  }
}

/// Битта маҳсулотнинг тафсилот саҳифаси (ўз `Scaffold`и билан).
class WholesaleProductDetailView extends StatefulWidget {
  const WholesaleProductDetailView({
    super.key,
    required this.product,
    this.catalog = const [],
    this.showNextHint = false,
  });

  final WholesaleProduct product;
  final List<WholesaleProduct> catalog;

  /// Охирида «кейинги маҳсулот учун юқорига суринг» кўрсатилсинми.
  final bool showNextHint;

  @override
  State<WholesaleProductDetailView> createState() =>
      _WholesaleProductDetailViewState();
}

class _WholesaleProductDetailViewState
    extends State<WholesaleProductDetailView> {
  /// Шу сеансда ҳисобланган товарлар — свайп билан қайтиб келганда ҳисоб
  /// қайта ошмасин.
  static final Set<String> _countedThisSession = <String>{};

  /// Танланган қадоқ (эга, 2026-10-31). Қадоқсиз маҳсулот — `default`.
  late String _packId = widget.product.effectivePacks.first.id;
  WholesalePack get _pack => widget.product.packById(_packId);

  late int _qty = _pack.moq;

  /// Қолдиқ — битта ҳужжат тинглагичи, экран ёпилганда ёпилади.
  late final Stream<WholesaleStock> _stock =
      WholesaleStockRepository().watch(widget.product.id);

  void _selectPack(String id) {
    if (id == _packId) return;
    setState(() {
      _packId = id;
      _qty = _pack.moq;
    });
  }

  late final List<WholesaleProduct> _similar =
      similarWholesale(widget.product, widget.catalog);
  late final List<WholesaleProduct> _sellerOthers =
      sellerOthers(widget.product, widget.catalog);

  @override
  void initState() {
    super.initState();
    if (_countedThisSession.add(widget.product.id)) {
      WholesaleProductsRepository().incrementViews(widget.product.id);
    }
    unawaited(_checkCanOrder());
  }

  /// «Буюртма бериш» (4-босқич): Хитой бозори эмас, ўз товари эмас ва
  /// дарвоза шу фойдаланувчини киритса кўринади. Ҳал қилувчи — сервер
  /// (квота `module_disabled` берса тугма яширинади, қўнғироқ қолади).
  final _ordersRepo = WholesaleOrdersRepository();
  String _uid = '';
  bool _canOrder = false;

  Future<void> _checkCanOrder() async {
    final p = widget.product;
    if (p.isChina) return;
    final uid = await walletPhoneId();
    if (uid.isEmpty || canonicalPhoneId(p.sellerId) == uid) {
      if (mounted && _canOrder) setState(() => _canOrder = false);
      return;
    }
    final gate = await _ordersRepo.gate();
    if (!mounted) return;
    setState(() {
      _uid = uid;
      _canOrder = gate.allows(uid);
    });
  }

  Future<void> _order() async {
    final orderId = await showWholesaleCheckoutSheet(
      context,
      product: widget.product,
      pack: _pack,
      qty: _qty,
      repository: _ordersRepo,
    );
    if (!mounted) return;
    if (orderId == null) {
      // Варақда дарвоза ёпиқ чиққан бўлса — тугма яширинсин.
      unawaited(_checkCanOrder());
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('wholesale_order_placed'))),
    );
    unawaited(Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WholesaleOrderDetailScreen(
          orderId: orderId,
          viewerId: _uid,
          repository: _ordersRepo,
        ),
      ),
    ));
  }

  Future<void> _call() async {
    final ok = await callPhone(widget.product.sellerId);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('wholesale_call_failed'))),
      );
    }
  }

  Future<void> _openVideo() async {
    final ok = await WholesaleVideoLink.openLinkedClip(
      context,
      sellerPhone: widget.product.sellerId,
      clipIds: widget.product.videoClipIds,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('wholesale_video_not_found'))),
      );
    }
  }

  void _openProduct(WholesaleProduct p) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WholesaleProductDetailScreen(
          product: p,
          catalog: widget.catalog,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final pack = _pack;
    final price = pack.priceForQty(_qty);
    final total = price * _qty;
    // Қадоқ расми бўлса — асосий расм ўрнига биринчи бўлиб (эга, 2026-10-31).
    final images = pack.hasPhoto
        ? [pack.photoUrl, ...p.imageUrls.where((u) => u != pack.photoUrl)]
        : p.imageUrls;
    final unitLabel = wholesaleUnitLabel(context, p.unit);
    // Асосий урғу — маҳсулот расми (эга, 2026-10-31): экран кенглигига тенг
    // квадрат, лекин баланд экранда ҳам пастдаги нарх/поғона кўриниши учун
    // экран баландлигининг 55% идан ошмайди (аввал қатъий 280 px эди).
    final screen = MediaQuery.sizeOf(context);
    final imageHeight =
        math.max(220.0, math.min(screen.width, screen.height * 0.55));
    const meta = TextStyle(fontSize: 12, height: 1.2, color: PdDark.muted);
    return ProductDetailDark(
      child: Scaffold(
        appBar: AppBar(title: Text(p.title, maxLines: 1)),
        body: ListView(
          // Контент қисқа бўлса ҳам охиридан ўтиб суриш сезилсин (свайп учун).
          physics: kEdgeSwipePhysics,
          children: [
            Stack(
              children: [
                AdImageSlider(
                  // Қадоқ алмашса слайдер бошидан (қадоқ расми) кўрсатсин.
                  key: ValueKey('wholesale-images-${pack.id}'),
                  imageUrls: images,
                  height: imageHeight,
                  backgroundColor: PdDark.surface2,
                ),
                if (p.videoClipIds.isNotEmpty)
                  Positioned(
                    left: 2,
                    bottom: 0,
                    child: _VideoChip(
                      label: context.tr('wholesale_watch_video'),
                      onTap: _openVideo,
                    ),
                  ),
              ],
            ),
            Padding(
              // Ёзувлар майда, қаторлар ораси минимал (эга, 2026-10-31).
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: PdDark.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.sellerCompanyName.isEmpty
                        ? context.tr('wholesale_seller_label')
                        : p.sellerCompanyName,
                    style: meta,
                  ),
                  if (p.hasPacks) ...[
                    const SizedBox(height: 6),
                    WholesalePackChips(
                      product: p,
                      selectedId: pack.id,
                      onSelected: _selectPack,
                    ),
                  ],
                  const SizedBox(height: 4),
                  // Танланган миқдордаги ҳақиқий бир дона нархи: поғона
                  // босилса ёки миқдор ўзгарса шу ердаги нарх ҳам ўзгаради.
                  Text(
                    '${formatPrice(price)} ${p.currencyLabel} / $unitLabel',
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: PdDark.brand,
                    ),
                  ),
                  // Хитой бозорида етказиш муддати — асосий саволлардан
                  // бири; киритилмаган бўлса умуман кўрсатилмайди.
                  if (p.isChina && (p.deliveryDays ?? 0) > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      context
                          .tr('wholesale_delivery_days')
                          .replaceAll('{days}', '${p.deliveryDays}'),
                      style: meta,
                    ),
                  ],
                  // Етказиш маълумоти (У1): вазн/ўлчам бўлса — кўрсатилади,
                  // бўлмаса харидор буни билсин (ҳақ ҳисобланмайди).
                  const SizedBox(height: 2),
                  if (pack.hasShippingData)
                    Text(
                      [
                        context.tr('wholesale_weight_line').replaceAll(
                            '{weight}', formatWeightG(pack.unitWeightG!)),
                        if (pack.unitDims != null)
                          context
                              .tr('wholesale_dims_line')
                              .replaceAll('{dims}', pack.unitDims!.label),
                      ].join(' · '),
                      style: meta,
                    )
                  else
                    Text(
                      context.tr('wholesale_no_shipping_data'),
                      style: meta.copyWith(color: const Color(0xFFF0A868)),
                    ),
                  StreamBuilder<WholesaleStock>(
                    stream: _stock,
                    builder: (context, snap) => WholesaleStockLine(
                      qty: snap.data?.of(pack.id),
                      unitLabel: unitLabel,
                    ),
                  ),
                  const SizedBox(height: 8),
                  WholesaleTierPicker(
                    // Қадоқ алмашса миқдор майдони ҳам янгидан.
                    key: ValueKey('wholesale-tiers-${pack.id}'),
                    product: p,
                    pack: p.hasPacks ? pack : null,
                    qty: _qty,
                    onQtyChanged: (q) => setState(() => _qty = q),
                  ),
                  if (p.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      p.description,
                      style: const TextStyle(
                        height: 1.3,
                        fontSize: 13,
                        color: PdDark.ink,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: PdDark.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.storefront_outlined,
                          size: 18, color: PdDark.brand),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p.sellerCompanyName.isEmpty
                              ? context.tr('wholesale_seller_label')
                              : p.sellerCompanyName,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: PdDark.ink,
                          ),
                        ),
                      ),
                    ]),
                  ),
                  if (_similar.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    WholesaleProductStrip(
                      title: context.tr('platform_store_similar'),
                      items: _similar,
                      onTap: _openProduct,
                    ),
                  ],
                  if (_sellerOthers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    WholesaleProductStrip(
                      title: context.tr('wholesale_seller_others'),
                      items: _sellerOthers,
                      onTap: _openProduct,
                    ),
                  ],
                  // Маълумот тугади — энди суриш кейинги маҳсулотга ўтади.
                  if (widget.showNextHint) ...[
                    const SizedBox(height: 16),
                    const _NextHint(),
                  ],
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: Material(
          color: PdDark.surface,
          elevation: 12,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // «Тахминий»: нарх сотувчи билан келишилади, бу
                        // буюртма суммаси эмас (чекаут йўқ, фақат қўнғироқ).
                        context.tr('wholesale_total_approx'),
                        style:
                            const TextStyle(fontSize: 12, color: PdDark.muted),
                      ),
                      Text(
                        '${formatPrice(total)} ${p.currencyLabel}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: PdDark.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  // Буюртма мумкин бўлса: қўнғироқ — ихчам (фақат белги,
                  // 48 dp), «Буюртма бериш» — асосий тугма. Қўнғироқ ҳамиша қолади.
                  if (_canOrder) ...[
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton.outlined(
                        key: const ValueKey('wholesale-call-compact'),
                        tooltip: context.tr('wholesale_call'),
                        onPressed: _call,
                        style: IconButton.styleFrom(
                          foregroundColor: PdDark.brand,
                          side: const BorderSide(color: PdDark.brand),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.call),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          key: const ValueKey('wholesale-order-button'),
                          onPressed: _order,
                          style: FilledButton.styleFrom(
                            backgroundColor: PdDark.brand,
                            foregroundColor: PdDark.brandInk,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.shopping_bag_outlined),
                          label: Text(
                            context.tr('wholesale_order_btn'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _call,
                        style: FilledButton.styleFrom(
                          backgroundColor: PdDark.brand,
                          foregroundColor: PdDark.brandInk,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.call),
                        label: Text(
                          context.tr('wholesale_call'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NextHint extends StatelessWidget {
  const _NextHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PdDark.line),
      ),
      child: Column(
        children: [
          const Icon(Icons.keyboard_double_arrow_up_rounded,
              color: PdDark.brand, size: 22),
          const SizedBox(height: 2),
          Text(
            context.tr('product_swipe_next_up'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: PdDark.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoChip extends StatelessWidget {
  const _VideoChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Кўринадиган «таблетка» аввалгидек (~32 dp), босиладиган майдон 48 dp баландликда.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: SizedBox(
          height: kWholesaleTapSize,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_circle_outline,
                          size: 16, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
