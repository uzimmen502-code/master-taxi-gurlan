import 'package:flutter/material.dart';
import '../../../core/utils/formatters.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../models/feed_item.dart';
import '../../../services/product_feed_service.dart';
import '../home_module_gate.dart';

/// `FeedSource` → Baseline moduleId (koʻrinish filtri uchun).
String _moduleIdFor(FeedSource s) => switch (s) {
      FeedSource.bread => 'bread',
      FeedSource.food => 'food',
      FeedSource.market => 'cheap_products_home',
    };

/// Чексиз аралаш маҳсулот лентаси (аввалги «Барчаси» таби) —
/// сарлавҳа ва табларсиз.
class ProductFeedSection extends StatefulWidget {
  const ProductFeedSection({super.key, required this.onProductTap});

  final void Function(FeedSource source) onProductTap;

  @override
  State<ProductFeedSection> createState() => _ProductFeedSectionState();
}

class _ProductFeedSectionState extends State<ProductFeedSection> {
  static const _sectionMuted = AppColors.sectionMuted;

  late final ProductFeedService _service;

  final List<FeedItem> _items = [];
  bool _loading = false;
  bool _exhausted = false;
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    _service = ProductFeedService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
  }

  Future<void> _loadMore() async {
    if (_loading || _exhausted) return;

    setState(() => _loading = true);

    try {
      // Ёпиқ модуллар бўш партия берса ҳам манбалар тугамагунча давом этамиз.
      for (var attempt = 0; attempt < 4; attempt++) {
        final batch = await _service.loadNextBatch();
        if (!mounted) return;

        if (batch.isEmpty) {
          setState(() {
            _loading = false;
            _initialLoadDone = true;
            _exhausted = true;
          });
          return;
        }

        final visibleBatch = batch
            .where((e) => HomeModuleGate.showInGrid(_moduleIdFor(e.source)))
            .toList(growable: false);

        final seen = _items.map((e) => e.dedupKey).toSet();
        final added = <FeedItem>[];
        for (final item in visibleBatch) {
          if (seen.add(item.dedupKey)) {
            added.add(item);
          }
        }

        if (added.isNotEmpty || _service.isExhausted) {
          setState(() {
            _loading = false;
            _initialLoadDone = true;
            _items.addAll(added);
            if (_service.isExhausted) _exhausted = true;
          });
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadDone = true;
        _exhausted = _service.isExhausted;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadDone = true;
        _exhausted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    if (_initialLoadDone && _items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            context.tr('home_feed_empty'),
            style: const TextStyle(
              fontSize: 12,
              color: _sectionMuted,
            ),
          ),
        ),
      );
    }

    if (_items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.0,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) => _FeedProductCard(
            item: _items[index],
            onTap: () => widget.onProductTap(_items[index].source),
          ),
        ),
        const SizedBox(height: 14),
        if (!_exhausted && !_loading)
          Center(
            child: _LoadMoreButton(
              label: context.tr('home_feed_load_more'),
              onPressed: _loadMore,
            ),
          )
        else if (_loading)
          Center(
            child: _LoadMoreButton(
              label: context.tr('home_feed_load_more'),
              onPressed: null,
              loading: true,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                context.tr('home_feed_no_more'),
                style: const TextStyle(
                  fontSize: 12,
                  color: _sectionMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  static const _brandGreen = AppColors.limeDeep;
  static const _chipInactiveBg = AppColors.limeHighlight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: _chipInactiveBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _brandGreen.withValues(alpha: 0.35)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _brandGreen.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: loading
                      ? _brandGreen.withValues(alpha: 0.7)
                      : _brandGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedProductCard extends StatelessWidget {
  const _FeedProductCard({
    required this.item,
    required this.onTap,
  });

  final FeedItem item;
  final VoidCallback onTap;

  static const _titleDark = AppColors.limeDeep;
  static const _priceGreen = AppColors.limeEdge;
  static const _cardBorder = AppColors.cardBorderMuted;

  String get _fallbackEmoji {
    switch (item.source) {
      case FeedSource.bread:
        return '🍞';
      case FeedSource.food:
        return '🍽️';
      case FeedSource.market:
        return '🛒';
    }
  }

  Color get _fallbackTint {
    switch (item.source) {
      case FeedSource.bread:
        return const Color(0xFFFFF3E0);
      case FeedSource.food:
        return const Color(0xFFFFEBEE);
      case FeedSource.market:
        return const Color(0xFFE3F2FD);
    }
  }

  @override
  Widget build(BuildContext context) {
    final priceText = context.tr('price_sum_short').replaceAll(
          '{price}',
          formatPrice(item.price),
        );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _cardBorder, width: 0.5),
          ),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 88,
                  width: double.infinity,
                  child: _FeedProductImage(
                    imageUrl: item.imageUrl,
                    fallbackEmoji: _fallbackEmoji,
                    fallbackTint: _fallbackTint,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _titleDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                priceText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _priceGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedProductImage extends StatelessWidget {
  const _FeedProductImage({
    required this.imageUrl,
    required this.fallbackEmoji,
    required this.fallbackTint,
  });

  final String imageUrl;
  final String fallbackEmoji;
  final Color fallbackTint;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();

    if (url.startsWith('assets/')) {
      return Image.asset(url, fit: BoxFit.contain);
    }

    if (url.isNotEmpty && isHttpImageUrl(url)) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return ColoredBox(
            color: fallbackTint,
            child: Center(
              child: Text(fallbackEmoji, style: const TextStyle(fontSize: 32)),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _FallbackBox(
          emoji: fallbackEmoji,
          tint: fallbackTint,
        ),
      );
    }

    if (url.isNotEmpty && isDataImageUrl(url)) {
      final bytes = decodeDataUrlImageBytes(url);
      if (bytes != null) {
        return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity);
      }
    }

    return _FallbackBox(emoji: fallbackEmoji, tint: fallbackTint);
  }
}

class _FallbackBox extends StatelessWidget {
  const _FallbackBox({required this.emoji, required this.tint});

  final String emoji;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: tint,
      child: Center(
        child: Text(emoji, style: const TextStyle(fontSize: 34)),
      ),
    );
  }
}
