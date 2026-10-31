import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../models/ad_model.dart';
import '../repositories/ads_repository.dart';
import '../widgets/ad_card.dart';
import '../widgets/market_grid.dart';

/// Аҳоли бозори: «Сотувчининг барча маҳсулотлари» (OLX каби, эга 2026-11-01).
///
/// Фақат ФАОЛ эълонлар ([AdsRepository.watchSellerActiveAds]); карточкадан
/// тафсилот очилади ва шу рўйхат ичида сурилади ([AdCard] → `adDetailsFor`).
class SellerAdsScreen extends StatefulWidget {
  const SellerAdsScreen({
    super.key,
    required this.ownerId,
    required this.sellerName,
    this.repository,
  });

  final String ownerId;
  final String sellerName;
  final AdsRepository? repository;

  @override
  State<SellerAdsScreen> createState() => _SellerAdsScreenState();
}

class _SellerAdsScreenState extends State<SellerAdsScreen> {
  late Stream<List<AdModel>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _load();
  }

  Stream<List<AdModel>> _load() =>
      (widget.repository ?? context.read<AdsRepository>()).watchSellerActiveAds(widget.ownerId);

  @override
  Widget build(BuildContext context) {
    final name = widget.sellerName.trim();
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('shop_item_seller_all'), style: const TextStyle(fontSize: 17)),
            if (name.isNotEmpty)
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
      body: StreamBuilder<List<AdModel>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return LoadErrorView(
              error: snap.error!,
              onRetry: () => setState(() => _stream = _load()),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final ads = snap.data!;
          if (ads.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.tr('ad_seller_ads_empty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: AppText.bodyMedium),
                ),
              ),
            );
          }
          return MarketProductGrid(
            itemCount: ads.length,
            itemBuilder: (_, i) => AdCard(ad: ads[i], catalog: ads),
          );
        },
      ),
    );
  }
}
