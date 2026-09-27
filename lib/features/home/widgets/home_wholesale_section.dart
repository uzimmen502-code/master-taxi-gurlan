import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'dart:math';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/session_shuffle.dart';
import '../../wholesale/models/wholesale_product.dart';
import '../../wholesale/repositories/wholesale_products_repository.dart';
import 'ava_list_row.dart';
import 'ava_section.dart';

/// Нарх поғонасининг қисқа кўриниши: «10+ дона».
///
/// Тавсиф талаби — «нарх поғонаси кўрсатилсин» ва Хитой бозорида
/// «минимал буюртма». Карточкада жой тор бўлгани учун ЭНГ ПАСТ поғона
/// (у айни пайтда минимал буюртма) кўрсатилади; тўлиқ поғоналар
/// маҳсулот саҳифасида.
String formatTierNote(BuildContext context, WholesaleProduct p) {
  if (p.priceTiers.isEmpty) return '';
  final t = p.priceTiers.first;
  return '${t.minQty}+ ${p.unit}';
}

/// Хитой бозори учун етказиш муддати: «14 кун». Маълум бўлмаса бўш.
String formatDelivery(BuildContext context, WholesaleProduct p) {
  final d = p.deliveryDays;
  if (d == null || d <= 0) return '';
  return '$d ${context.tr('home_delivery_days')}';
}

/// 7 ва 8-бўлимлар: улгуржи бозори ва Хитой бозори.
///
/// Иккаласи ҳам БИР ХИЛ архитектурада (эга қарори): ўша коллекция, ўша
/// қоидалар, фақат `market` майдони билан ажралади — шунинг учун битта
/// виджет.
class HomeWholesaleSection extends StatefulWidget {
  const HomeWholesaleSection({
    super.key,
    required this.market,
    required this.titleKey,
    required this.onOpenAll,
    required this.onOpenProduct,
  });

  /// [WholesaleProduct.marketWholesale] ёки [WholesaleProduct.marketChina].
  final String market;
  final String titleKey;

  final VoidCallback onOpenAll;
  final void Function(WholesaleProduct product) onOpenProduct;

  /// Икки қатор тўлиши учун 5 эмас, 10 та (қаранг: [AvaProductShelf]).
  static const limit = 10;

  @override
  State<HomeWholesaleSection> createState() => _HomeWholesaleSectionState();
}

class _HomeWholesaleSectionState extends State<HomeWholesaleSection> {
  final _repo = WholesaleProductsRepository();
  final _scroll = ScrollController();
  final Random _rnd = sessionRandom();
  StreamSubscription<List<WholesaleProduct>>? _sub;

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<WholesaleProduct> _items = const [];

  /// Чексиз скролл: охирига яқинлашганда яна шунча сўралади.
  int _limit = HomeWholesaleSection.limit;
  bool _endReached = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _listen();
  }

  void _onScroll() {
    if (_endReached || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels < pos.maxScrollExtent - 240) return;
    _limit += HomeWholesaleSection.limit;
    _listen(initial: false);
  }

  void _listen({bool initial = true}) {
    _sub?.cancel();
    if (initial && mounted) {
      setState(() => _status = AvaSectionStatus.loading);
    }
    // Улгуржи бозор ҳудудга боғланмаган — сотувчилар вилоятлараро
    // ишлайди, шунинг учун бу бўлимда туман филтри йўқ.
    _sub = _repo
        .getActiveProducts(
          limit: _limit,
          market: widget.market,
        )
        .listen(
      (list) {
        if (!mounted) return;
        setState(() {
          // Аввал кўрсатилганлар ўрнида қолади, янгилари аралашиб
          // охирига қўшилади (сеанс уруғи — ҳар очилишда бошқа тартиб).
          _items = mergeShuffled(
            current: _items,
            incoming: list,
            idOf: (p) => p.id,
            random: _rnd,
          );
          _endReached = list.length < _limit;
          _status =
              _items.isEmpty ? AvaSectionStatus.empty : AvaSectionStatus.ready;
        });
      },
      onError: (Object e) {
        debugPrint('[HomeWholesale] $e');
        if (mounted) setState(() => _status = AvaSectionStatus.error);
      },
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AvaSection(
      moduleId: 'wholesale_market',
      title: context.tr(widget.titleKey),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      skeletonRows: 1,
      // Икки қатор, ёнга скролл (қаранг: [AvaProductShelf]).
      child: AvaProductShelf(
        // Қатъий 214 эмас — шрифт 130% бўлганда матн карточкадан тошиб
        // кетарди (`avaTileListHeight` изоҳига қаранг).
        rowHeight: avaTileListHeight(context),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final p = _items[i];
          final cover = p.imageUrls.isEmpty ? '' : p.imageUrls.first;
          return AvaTileCard(
            title: p.title,
            price: p.basePrice > 0
                ? '${context.tr('home_price_from')} '
                    '${formatPrice(p.basePrice)} '
                    '${p.currencyLabel}'
                : null,
            priceNote: formatTierNote(context, p),
            // Хитой бозорида етказиш муддати, улгуржида сотувчи номи.
            footnote: p.isChina
                ? (formatDelivery(context, p).isNotEmpty
                    ? formatDelivery(context, p)
                    : p.sellerCompanyName)
                : p.sellerCompanyName,
            onTap: () => widget.onOpenProduct(p),
            image: cover.startsWith('http')
                ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover)
                : null,
          );
        },
      ),
    );
  }
}
