import 'package:flutter/material.dart';
import '../../../core/utils/formatters.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../models/feed_item.dart';
import '../../../services/product_feed_service.dart';

/// «Barcha mahsulotlar» — cheksiz mahsulotlar lentasi (non / taom / bozor).
class ProductFeedSection extends StatefulWidget {
  const ProductFeedSection({super.key, required this.onProductTap});

  final void Function(FeedSource source) onProductTap;

  @override
  State<ProductFeedSection> createState() => _ProductFeedSectionState();
}

class _ProductFeedSectionState extends State<ProductFeedSection> {
  static const _titleDark = Color(0xFF1A3A20);
  static const _sectionMuted = AppColors.sectionMuted;

  late final ProductFeedService _service;

  final List<FeedItem> _items = [];
  FeedSource? _activeTab;
  bool _loading = false;
  bool _exhausted = false;
  bool _initialLoadDone = false;

  List<({String label, FeedSource? source})> _tabs(BuildContext context) => [
        (label: context.tr('all_categories'), source: null),
        (label: context.tr('home_feed_tab_bread'), source: FeedSource.bread),
        (label: context.tr('home_feed_tab_food'), source: FeedSource.food),
        (label: context.tr('home_feed_tab_market'), source: FeedSource.market),
      ];

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
      final batch = _activeTab == null
          ? await _service.loadNextBatch()
          : await _service.loadNextSourceBatch(_activeTab!);

      if (!mounted) return;

      setState(() {
        _loading = false;
        _initialLoadDone = true;
        if (batch.isEmpty) {
          _exhausted = true;
        } else {
          final seen = _items.map((e) => e.dedupKey).toSet();
          for (final item in batch) {
            if (seen.add(item.dedupKey)) {
              _items.add(item);
            }
          }
        }
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

  void _onTabSelected(FeedSource? tab) {
    if (_activeTab == tab) return;

    _service.reset();
    setState(() {
      _activeTab = tab;
      _items.clear();
      _exhausted = false;
      _initialLoadDone = false;
      _loading = false;
    });
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('home_feed_title'),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _titleDark,
          ),
        ),
        const SizedBox(height: 10),
        _FeedTabBar(
          tabs: tabs,
          activeTab: _activeTab,
          onSelected: _onTabSelected,
        ),
        const SizedBox(height: 12),
        if (_loading && _items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          )
        else if (_initialLoadDone && _items.isEmpty)
          Padding(
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
          )
        else if (_items.isNotEmpty) ...[
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
      ],
    );
  }
}

class _FeedTabBar extends StatelessWidget {
  const _FeedTabBar({
    required this.tabs,
    required this.activeTab,
    required this.onSelected,
  });

  final List<({String label, FeedSource? source})> tabs;
  final FeedSource? activeTab;
  final ValueChanged<FeedSource?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _FeedTabChip(
              label: tabs[i].label,
              selected: activeTab == tabs[i].source,
              onTap: () => onSelected(tabs[i].source),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedTabChip extends StatelessWidget {
  const _FeedTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const _brandGreen = Color(0xFF36A63A);
  static const _chipInactiveBg = Color(0xFFEAF5E4);
  static const _chipInactiveText = Color(0xFF1A3A20);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? _brandGreen : _chipInactiveBg,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : _chipInactiveText,
            ),
          ),
        ),
      ),
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

  static const _brandGreen = Color(0xFF36A63A);
  static const _chipInactiveBg = Color(0xFFEAF5E4);

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

  static const _titleDark = Color(0xFF1A3A20);
  static const _priceGreen = Color(0xFF2E5C1E);
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
