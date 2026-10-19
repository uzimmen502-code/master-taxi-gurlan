import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/brand_labels.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/platform_product.dart';
import 'market_grid.dart';
import '../../platform_store/controllers/platform_store_controller.dart';
import '../../platform_store/screens/platform_product_detail_screen.dart';

/// Онлайн бозор лентасидаги платформа товари (AVA белгиси).
///
/// Босилганда АЙНАН ШУ товарнинг тафсилоти очилади (2026-09-29).
/// Аввал бутун `PlatformStoreScreen` очилар эди — фойдаланувчи лентадан
/// чиқиб кетар, босган товари эса қайси экранда экани номаълум қолар,
/// яъни AVA товари лентага «аралашмай» алоҳида ажралиб турар эди.
/// Эълон ва дўкон карталари аллақачон шундай ишлайди: карта → тафсилот.
class PlatformMarketCard extends StatelessWidget {
  const PlatformMarketCard({
    super.key,
    required this.product,
    this.catalog = const [],
    this.wholesale = false,
  });

  final PlatformProduct product;

  /// Лентадаги бошқа AVA товарлари — тафсилотда суриб ўтиш учун.
  final List<PlatformProduct> catalog;

  /// Улгуржи бозор лентасида — нарх «дан ... / дона» кўринишида ва
  /// минимал буюртма кўрсатилади (2026-09-29).
  final bool wholesale;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => openPlatformProductDetail(context, product, catalog),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: MarketGridMetrics.imageAspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Image(url: product.coverImageUrl),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.button,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'AVA',
                        style: TextStyle(
                          color: AppColors.onPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Сотувчи номи ўрнида — «AVA» (2026-10-07: «AVA дўкони» йўқ, AVA
            // товари Улгуржи бозорнинг бир сотувчиси).
            MarketCardText(
              title: product.name,
              price: wholesale
                  ? _wholesalePriceLine(product)
                  : formatMoney(product.displayPrice),
              caption: wholesale
                  ? _wholesaleSubLine(product)
                  : BrandLabels.brand,
            ),
          ],
        ),
      ),
    );
  }
}

/// Улгуржи лентасидаги асосий нарх қатори.
///
/// Эга қарори (2026-10-06): поғонаси қўйилмаган товарда базадаги нарх —
/// ўрта поғона, карточкада «10–50 дона: 10 000 сўм». Админ поғона қўйган
/// товар — аввалгидек «дан 9 000 сўм / дона».
String platformWholesalePriceLine(PlatformProduct p) {
  final mid = p.midTier;
  if (p.hasDerivedTiers && mid != null) {
    return '${p.tierRangeLabel(1)} ${p.unit}: ${formatMoney(mid.price)}';
  }
  return '${p.effectiveTiers.length > 1 ? 'дан ' : ''}'
      '${formatMoney(p.wholesaleBasePrice)} / ${p.unit}';
}

/// Иккинчи қатор: ҳисобланган поғонада кам миқдор нархи («1–9 дона:
/// 10 500 сўм» — харидор 1 дона олса қанча тўлашини кўрсин), акс ҳолда МОҚ.
String platformWholesaleSubLine(PlatformProduct p) {
  final t = p.effectiveTiers;
  if (p.hasDerivedTiers && t.isNotEmpty) {
    return '${p.tierRangeLabel(0)} ${p.unit}: ${formatMoney(t.first.price)}';
  }
  return 'МОҚ ${p.wholesaleMinQty} ${p.unit}';
}

/// Бош саҳифадаги тор карточка (148 px) учун ҚИСҚА нарх ва изоҳ.
///
/// [platformWholesalePriceLine] («10–50 дона: 10 000 сўм») тор карточкада
/// икки қаторга ўтиб, қатор баландлигидан тошарди. Шунинг учун нарх ва
/// оралиқ устма-уст: «10 000 сўм» / «10–50 дона» — сотувчи товари
/// карточкаси билан бир хил шакл («9 000 сўм» / «10+ дона»).
({String price, String note}) platformShelfPrice(PlatformProduct p) {
  if (p.hasDerivedTiers && p.midTier != null) {
    return (
      price: formatMoney(p.midTier!.price),
      note: '${p.tierRangeLabel(1)} ${p.unit}',
    );
  }
  if (p.effectiveTiers.isNotEmpty) {
    return (
      price: formatMoney(p.wholesaleBasePrice),
      note: '${p.tierRangeLabel(0)} ${p.unit}',
    );
  }
  return (price: formatMoney(p.price), note: '');
}

/// AVA товари тафсилоти — лента, бош саҳифа ва қидирувдан бир хил.
///
/// Тафсилот экрани саватни `PlatformStoreController`дан олади, шунинг
/// учун у шу маршрутда яратилади ва маршрут ёпилганда ўзи тозаланади.
Future<void> openPlatformProductDetail(
  BuildContext context,
  PlatformProduct product, [
  List<PlatformProduct> catalog = const [],
]) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<PlatformStoreController>(
        create: (_) {
          final c = PlatformStoreController();
          unawaited(c.init());
          return c;
        },
        child: PlatformProductDetailScreen(
          product: product,
          catalog: catalog.isEmpty ? [product] : catalog,
        ),
      ),
    ),
  );
}

String _wholesalePriceLine(PlatformProduct p) => platformWholesalePriceLine(p);
String _wholesaleSubLine(PlatformProduct p) => platformWholesaleSubLine(p);

class _Image extends StatelessWidget {
  const _Image({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    if (u.isNotEmpty && isHttpImageUrl(u)) {
      // contain: катта расм четлари қирқилмай катакка сиғиб кичраяди;
      // қолган жойни cardImageBg тўлдиради (ега 2026-10-19).
      return ColoredBox(
        color: AppColors.cardImageBg,
        child: CachedNetworkImage(
          imageUrl: u,
          fit: BoxFit.contain,
          placeholder: (_, __) => const ColoredBox(
            color: AppColors.cardImageBg,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (_, __, ___) => const ColoredBox(
            color: AppColors.cardImageBg,
            child: Icon(Icons.broken_image),
          ),
        ),
      );
    }
    if (u.isNotEmpty && isDataImageUrl(u)) {
      final bytes = decodeDataUrlImageBytes(u);
      if (bytes != null) {
        return ColoredBox(
          color: AppColors.cardImageBg,
          child: Image.memory(bytes, fit: BoxFit.contain),
        );
      }
    }
    return const ColoredBox(
      color: AppColors.cardImageBg,
      child: Center(child: Icon(Icons.storefront, size: 40)),
    );
  }
}
