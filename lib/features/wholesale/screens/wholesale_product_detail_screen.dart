import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/product_detail_dark.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../core/widgets/edge_swipe_pager.dart';
import '../../ads/widgets/ad_image_slider.dart';
import '../../deal_chat/open_deal_chat.dart';
import '../widgets/wholesale_detail_actions.dart';
import '../models/wholesale_product.dart';
import '../repositories/wholesale_orders_repository.dart';
import '../repositories/wholesale_products_repository.dart';
import '../repositories/wholesale_stock_repository.dart';
import 'wholesale_order_detail_screen.dart';
import '../widgets/wholesale_checkout_sheet.dart';
import '../widgets/wholesale_compact_detail_parts.dart';
import '../services/wholesale_video_link.dart';
import '../utils/wholesale_labels.dart';
import '../utils/wholesale_similar.dart';
import '../widgets/wholesale_pack_chips.dart';
import '../widgets/wholesale_product_strip.dart';
import 'wholesale_seller_products_screen.dart';
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
    // бошқа ранг кўринмасин. «‹ N / M ›» тугмаси олиб ташланди (эга, 2026-11-01:
    // суринганда нарх устига тушиб, матнни ёпарди) — ўтиш суриш билан ва
    // «Кейинги маҳсулот учун юқорига суринг» кўрсатмаси билан.
    return ColoredBox(
      color: PdDark.bg,
      child: EdgeSwipePager(
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

  void _selectPack(String id) {
    if (id == _packId) return;
    setState(() {
      _packId = id;
      // Қадоқ алмашса миқдор шу қадоқнинг минимумидан бошланади.
      _qty = _pack.moq;
    });
  }

  /// Улгуржи (Б вариант): танланган миқдор — фақат кўрсатиш (≈ сумма),
  /// буюртма нархини сервер ҳисоблайди (CLAUDE.md 18).
  late int _qty = _pack.moq;

  /// Қолдиқ (`wholesale_stock`) — фақат Улгуржида, битта ҳужжат тинглагичи.
  Stream<WholesaleStock>? _stock;

  // Улгуржи — намуна экран қоидаси ([similarWholesaleAny]); Хитой — аввалгидек.
  late final List<WholesaleProduct> _similar = widget.product.isChina
      ? similarWholesale(widget.product, widget.catalog)
      : similarWholesaleAny(widget.product, widget.catalog);

  /// Жорий фойдаланувчи (канон рақам); бўш — меҳмон ёки ҳали ўқилмади.
  String _myUid = '';
  bool _writeBusy = false;

  @override
  void initState() {
    super.initState();
    if (_countedThisSession.add(widget.product.id)) {
      WholesaleProductsRepository().incrementViews(widget.product.id);
    }
    if (!widget.product.isChina) {
      _stock = WholesaleStockRepository().watch(widget.product.id);
    }
    _loadMe();
  }

  Future<void> _loadMe() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    if (mounted && uid != _myUid) setState(() => _myUid = uid);
    unawaited(_checkCanOrder());
  }

  /// Онлайн «Буюртма бериш» (эга, 2026-11-13: «албатта қайтарамиз» — 01.11 да олиб
  /// ташланган эди): Улгуржида, ўз товари эмас ва буюртма дарвозаси шу
  /// фойдаланувчини киритса. Ҳал қилувчи — сервер (`module_disabled` бўлса
  /// варақ ёпилади ва тугма яширинади; қўнғироқ ва чат қолади).
  final _ordersRepo = WholesaleOrdersRepository();
  bool _canOrder = false;

  Future<void> _checkCanOrder() async {
    final p = widget.product;
    final uid = _myUid;
    final allowed = !p.isChina &&
        uid.length >= 11 &&
        canonicalPhoneId(p.sellerId) != uid &&
        (await _ordersRepo.gate()).allows(uid);
    if (mounted && allowed != _canOrder) setState(() => _canOrder = allowed);
  }

  Future<void> _placeOrder(int qty) async {
    final orderId = await showWholesaleCheckoutSheet(
      context,
      product: widget.product,
      pack: _pack,
      qty: qty,
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
          viewerId: _myUid,
          repository: _ordersRepo,
        ),
      ),
    ));
  }

  /// «Буюртма ёзиш» → эълон эгаси билан чат (эга қарори 2026-11-01).
  /// [draft] — Улгуржида танланган миқдор матни чат майдонига (эга, 2026-11-02).
  Future<void> _writeOrder({String? draft}) async {
    if (_writeBusy) return;
    // Меҳмон огоҳлантириши, чат очиш ва хато матни — умумий ([openDealChatFlow]).
    if (_myUid.length >= 11) setState(() => _writeBusy = true);
    try {
      await openDealChatFlow(context,
          productId: widget.product.id, myUid: _myUid, initialProduct: widget.product, draft: draft);
    } finally {
      if (mounted) setState(() => _writeBusy = false);
    }
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
    // Улгуржи — Аралаш бозордаги AVA маҳсулоти экрани андозасида (эга,
    // 2026-11-02, «Б вариант»); Хитой ҳозирча эски кўринишда.
    if (!widget.product.isChina) {
      final stream = _stock;
      if (stream == null) return _buildCompact(context, null);
      return StreamBuilder<WholesaleStock>(
        stream: stream,
        builder: (context, snap) => _buildCompact(context, snap.data?.of(_packId)),
      );
    }
    return _buildChina(context);
  }

  /// Улгуржи тафсилоти («Б вариант»): расм ~28% баландлик, ном, сотувчи,
  /// қадоқ, «нарх / бирлик ··· Қолди: N», поғоналар, 2 қатор тавсиф,
  /// ўхшашлар; пастда [− N +] [📞] [Буюртма ёзиш · ≈ сумма].
  Widget _buildCompact(BuildContext context, int? stockQty) {
    final p = widget.product;
    final pack = _pack;
    final images = pack.hasPhoto
        ? [pack.photoUrl, ...p.imageUrls.where((u) => u != pack.photoUrl)]
        : p.imageUrls;
    final unitLabel = wholesaleUnitLabel(context, p.unit);
    final maxQty = (stockQty != null && stockQty > 0) ? stockQty : kWholesaleMaxQty;
    final qty = clampCompactQty(_qty, moq: pack.moq, max: maxQty);
    final price = pack.priceForQty(qty);
    final h = MediaQuery.sizeOf(context).height;
    const meta = TextStyle(fontSize: 11, height: 1.2, color: PdDark.muted);
    void setQty(int q) => setState(() => _qty = clampCompactQty(q, moq: pack.moq, max: maxQty));

    return ProductDetailDark(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            context.tr('wholesale_title'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 0.15),
          ),
        ),
        body: ListView(
          physics: kEdgeSwipePhysics,
          children: [
            Stack(
              children: [
                AdImageSlider(
                  key: ValueKey('wholesale-images-${pack.id}'),
                  imageUrls: images,
                  height: (h * 0.28).clamp(150.0, 240.0),
                  backgroundColor: PdDark.surface,
                ),
                if (p.videoClipIds.isNotEmpty)
                  Positioned(
                    left: 2,
                    bottom: 0,
                    child: _VideoChip(label: context.tr('wholesale_watch_video'), onTap: _openVideo),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, height: 1.2, fontWeight: FontWeight.w700, color: PdDark.ink),
                  ),
                  _SellerLink(product: p),
                  if (p.hasPacks) ...[
                    WholesalePackChips(product: p, selectedId: pack.id, onSelected: _selectPack),
                    const SizedBox(height: 6),
                  ],
                  WholesalePriceStockRow(
                    priceText: '${formatPrice(price)} ${p.currencyLabel}',
                    unitLabel: unitLabel,
                    stockQty: stockQty,
                  ),
                  // Етказиш маълумоти (У1) — битта майда қатор.
                  const SizedBox(height: 2),
                  Text(
                    pack.hasShippingData
                        ? [
                            context
                                .tr('wholesale_weight_line')
                                .replaceAll('{weight}', formatWeightG(pack.unitWeightG!)),
                            if (pack.unitDims != null)
                              context.tr('wholesale_dims_line').replaceAll('{dims}', pack.unitDims!.label),
                          ].join(' · ')
                        : context.tr('wholesale_no_shipping_data'),
                    style: pack.hasShippingData ? meta : meta.copyWith(color: const Color(0xFFF0A868)),
                  ),
                  if (pack.priceTiers.length > 1) ...[
                    const SizedBox(height: 8),
                    WholesaleTierRow(
                      tiers: pack.priceTiers,
                      qty: qty,
                      unitLabel: unitLabel,
                      onPick: setQty,
                    ),
                  ],
                  if (p.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _CompactDescription(text: p.description.trim()),
                  ],
                  if (_similar.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    WholesaleProductStrip(
                      title: context.tr('platform_store_similar'),
                      items: _similar,
                      onTap: _openProduct,
                    ),
                  ],
                  if (widget.showNextHint) ...[
                    const SizedBox(height: 8),
                    const _NextHint(),
                  ],
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: Material(
          color: PdDark.surface,
          elevation: 8,
          shadowColor: Colors.black,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: WholesaleCompactBottomBar(
                qty: qty,
                minQty: pack.moq,
                maxQty: maxQty,
                onQtyChanged: setQty,
                totalText: '≈ ${formatPrice(price * qty)} ${p.currencyLabel}',
                onCall: _call,
                onWriteOrder: () => _writeOrder(
                  draft: wholesaleOrderDraft(
                    template: context.tr('deal_chat_order_draft'),
                    title: p.title,
                    packLabel: p.hasPacks ? pack.label : '',
                    qty: qty,
                    unitLabel: unitLabel,
                    totalText: '${formatPrice(price * qty)} ${p.currencyLabel}',
                  ),
                ),
                showWriteOrder: wholesaleShowWriteOrder(myUid: _myUid, sellerId: p.sellerId),
                writeBusy: _writeBusy,
                onPlaceOrder: _canOrder ? () => _placeOrder(qty) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Хитой бозори — аввалги кўриниш (эга, 2026-11-02: «ҳозирча фақат улгуржи»).
  Widget _buildChina(BuildContext context) {
    final p = widget.product;
    final pack = _pack;
    // Миқдор экранда танланмайди (эга, 2026-11-01: чат ёки телефонда
    // келишилади) — минимал миқдордаги бир дона нархи.
    final price = pack.priceForQty(pack.moq);
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
        // Ном фақат шу ерда (эга, 2026-11-01) — узун ном 2 қаторда тўлиқроқ кўринсин.
        appBar: AppBar(
          title: Text(
            p.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, height: 1.2, fontWeight: FontWeight.w600),
          ),
        ),
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
                  // Сотувчи — битта жойда (эга, 2026-11-01): босилса унинг барча маҳсулотлари.
                  _SellerLink(product: p),
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
                  // Бир нечта поғона бўлса — «дан» (кўпроқ олса нарх келишилади; рўйхатдагидек).
                  Text(
                    '${pack.priceTiers.length > 1 ? '${context.tr('home_price_from')} ' : ''}'
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
                  if (p.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      context.tr('wholesale_description_title'),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PdDark.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.description,
                      style: const TextStyle(
                        height: 1.3,
                        fontSize: 13,
                        color: PdDark.ink,
                      ),
                    ),
                  ],
                  if (_similar.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    WholesaleProductStrip(
                      title: context.tr('platform_store_similar'),
                      items: _similar,
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
              // Сутли (молочный) ранг (эга, 2026-11-01): «Қўнғироқ қилиш» + «Буюртма ёзиш».
              child: WholesaleDetailActions(
                onCall: _call,
                onWriteOrder: _writeOrder,
                // Ўз эълонида йўқ (сервер ҳам рад этади: OWN_PRODUCT).
                showWriteOrder: wholesaleShowWriteOrder(myUid: _myUid, sellerId: p.sellerId),
                writeBusy: _writeBusy,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Сотувчи номи — босилса «Сотувчининг барча маҳсулотлари» (алоҳида катта тугма ўрнига).
class _SellerLink extends StatelessWidget {
  const _SellerLink({required this.product});

  final WholesaleProduct product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final name = p.sellerCompanyName.trim().isEmpty
        ? context.tr('wholesale_seller_label')
        : p.sellerCompanyName.trim();
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.storefront_outlined, size: 16, color: PdDark.muted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w600, color: PdDark.ink),
          ),
        ),
        if (p.sellerId.isNotEmpty) const Icon(Icons.chevron_right, size: 18, color: PdDark.muted),
      ],
    );
    if (p.sellerId.isEmpty) return row;
    return Semantics(
      button: true,
      label: '$name — ${context.tr('shop_item_seller_all')}',
      child: InkWell(
        key: const ValueKey('wholesale_go_seller'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WholesaleSellerProductsScreen(
              sellerId: p.sellerId,
              sellerName: p.sellerCompanyName,
              market: p.isChina ? WholesaleProduct.marketChina : WholesaleProduct.marketWholesale,
            ),
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Align(alignment: Alignment.centerLeft, child: row),
        ),
      ),
    );
  }
}

/// «Кейинги маҳсулот учун юқорига суринг» — ихчам кулранг ёзув (эга, 2026-11-01).
class _NextHint extends StatelessWidget {
  const _NextHint();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.keyboard_arrow_up_rounded, color: PdDark.muted, size: 18),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            context.tr('product_swipe_next_up'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: PdDark.muted),
          ),
        ),
      ],
    );
  }
}

/// Тавсиф — 2 қатор (намуна экрандагидек); босилса тўлиқ очилади/ёпилади,
/// узун матн йўқолмасин.
class _CompactDescription extends StatefulWidget {
  const _CompactDescription({required this.text});

  final String text;

  @override
  State<_CompactDescription> createState() => _CompactDescriptionState();
}

class _CompactDescriptionState extends State<_CompactDescription> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('wholesale-description'),
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _open = !_open),
      child: Text(
        widget.text,
        maxLines: _open ? null : 2,
        overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, height: 1.3, color: PdDark.ink.withValues(alpha: 0.8)),
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
