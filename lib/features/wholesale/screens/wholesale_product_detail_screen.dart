import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/product_detail_dark.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../core/widgets/edge_swipe_pager.dart';
import '../../ads/widgets/ad_image_slider.dart';
import '../models/wholesale_product.dart';
import '../repositories/wholesale_products_repository.dart';
import '../services/wholesale_video_link.dart';
import '../utils/wholesale_labels.dart';
import '../utils/wholesale_similar.dart';
import '../widgets/wholesale_product_strip.dart';
import '../widgets/wholesale_tier_picker.dart';

/// Маҳсулот тафсилоти — улгуржи битим телефон орқали келишилади,
/// checkout/wallet йўқ (`yuk_local`даги "фақат қўнғироқ" андозаси).
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

  late int _qty = widget.product.moq;
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
    final price = p.priceForQty(_qty);
    final total = price * _qty;
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
                  imageUrls: p.imageUrls,
                  height: 280,
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
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: PdDark.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.sellerCompanyName.isEmpty
                        ? context.tr('wholesale_seller_label')
                        : p.sellerCompanyName,
                    style: const TextStyle(fontSize: 13, color: PdDark.muted),
                  ),
                  const SizedBox(height: 8),
                  // Танланган миқдордаги ҳақиқий бир дона нархи: поғона
                  // босилса ёки миқдор ўзгарса шу ердаги нарх ҳам ўзгаради.
                  Text(
                    '${formatPrice(price)} ${p.currencyLabel} / ${wholesaleUnitLabel(context, p.unit)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: PdDark.brand,
                    ),
                  ),
                  // Хитой бозорида етказиш муддати — асосий саволлардан
                  // бири; киритилмаган бўлса умуман кўрсатилмайди.
                  if (p.isChina && (p.deliveryDays ?? 0) > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      context
                          .tr('wholesale_delivery_days')
                          .replaceAll('{days}', '${p.deliveryDays}'),
                      style: const TextStyle(fontSize: 13, color: PdDark.muted),
                    ),
                  ],
                  // Етказиш маълумоти (У1): вазн/ўлчам бўлса — кўрсатилади,
                  // бўлмаса харидор буни билсин (ҳақ ҳисобланмайди).
                  const SizedBox(height: 4),
                  if (p.hasShippingData)
                    Text(
                      [
                        context.tr('wholesale_weight_line').replaceAll(
                            '{weight}', formatWeightG(p.unitWeightG!)),
                        if (p.unitDims != null)
                          context
                              .tr('wholesale_dims_line')
                              .replaceAll('{dims}', p.unitDims!.label),
                      ].join(' · '),
                      style: const TextStyle(fontSize: 13, color: PdDark.muted),
                    )
                  else
                    Text(
                      context.tr('wholesale_no_shipping_data'),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFF0A868)),
                    ),
                  const SizedBox(height: 16),
                  WholesaleTierPicker(
                    product: p,
                    qty: _qty,
                    onQtyChanged: (q) => setState(() => _qty = q),
                  ),
                  if (p.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      p.description,
                      style: const TextStyle(
                        height: 1.4,
                        fontSize: 14,
                        color: PdDark.ink,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: PdDark.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.storefront_outlined,
                          color: PdDark.brand),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p.sellerCompanyName.isEmpty
                              ? context.tr('wholesale_seller_label')
                              : p.sellerCompanyName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: PdDark.ink,
                          ),
                        ),
                      ),
                    ]),
                  ),
                  if (_similar.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    WholesaleProductStrip(
                      title: context.tr('platform_store_similar'),
                      items: _similar,
                      onTap: _openProduct,
                    ),
                  ],
                  if (_sellerOthers.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    WholesaleProductStrip(
                      title: context.tr('wholesale_seller_others'),
                      items: _sellerOthers,
                      onTap: _openProduct,
                    ),
                  ],
                  // Маълумот тугади — энди суриш кейинги маҳсулотга ўтади.
                  if (widget.showNextHint) ...[
                    const SizedBox(height: 24),
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
