import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/brand_labels.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/platform_product.dart';
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
  });

  final PlatformProduct product;

  /// Лентадаги бошқа AVA товарлари — тафсилотда суриб ўтиш учун.
  final List<PlatformProduct> catalog;

  /// Тафсилот экрани саватни `PlatformStoreController`дан олади, шунинг
  /// учун у шу маршрутда яратилади ва маршрут ёпилганда ўзи тозаланади
  /// (`PlatformStoreScreen` билан бир хил андоза).
  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
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

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openDetail(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
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
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppText.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatMoney(product.price),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppText.bodySmall,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${BrandLabels.brand} ${context.tr('platform_store_title_suffix')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Image extends StatelessWidget {
  const _Image({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    if (u.isNotEmpty && isHttpImageUrl(u)) {
      return CachedNetworkImage(
        imageUrl: u,
        fit: BoxFit.cover,
        placeholder: (_, __) => const ColoredBox(
          color: AppColors.cardImageBg,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => const ColoredBox(
          color: AppColors.cardImageBg,
          child: Icon(Icons.broken_image),
        ),
      );
    }
    if (u.isNotEmpty && isDataImageUrl(u)) {
      final bytes = decodeDataUrlImageBytes(u);
      if (bytes != null) {
        return Image.memory(bytes, fit: BoxFit.cover);
      }
    }
    return const ColoredBox(
      color: AppColors.cardImageBg,
      child: Center(child: Icon(Icons.storefront, size: 40)),
    );
  }
}
