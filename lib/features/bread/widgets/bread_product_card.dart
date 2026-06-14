import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/bread_product.dart';
import '../../../core/theme/app_theme.dart';

/// Нон каталогидаги бирор маҳсулот картаси (Ёпиш/Тайёр/Той).
class BreadProductCard extends StatefulWidget {
  const BreadProductCard({
    super.key,
    required this.product,
    required this.count,
    required this.price,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
  });

  final BreadProduct product;
  final int count;
  final int price;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  State<BreadProductCard> createState() => _BreadProductCardState();
}

class _BreadProductCardState extends State<BreadProductCard> {
  bool _imageZoomed = false;

  static const _primary = AppColors.primary;
  static const _orange = AppColors.primary;

  BreadProduct get product => widget.product;

  void _toggleImageZoom() {
    if (!product.isYopish) return;
    setState(() => _imageZoomed = !_imageZoomed);
  }

  String _toySizeLabel(AppLocalizations loc) {
    final c = product.category.trim();
    if (c.isNotEmpty) return c;
    return loc.translate('bread_category_wedding');
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final accentColor = product.isYopish ? _orange : _primary;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: Stack(children: [
          Container(
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: GestureDetector(
                onTap: product.isYopish ? _toggleImageZoom : null,
                behavior: HitTestBehavior.opaque,
                child: AnimatedScale(
                  scale: _imageZoomed ? 1.45 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  child: _imageWidget(),
                ),
              ),
            ),
          ),
          if (product.isToy)
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.purple.shade600,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(
                  _toySizeLabel(loc),
                  style: const TextStyle(
                    fontSize: AppText.labelTiny,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (product.isReady && product.totalStock > 0)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: product.isSoldOut
                      ? Colors.red.shade700
                      : product.remaining <= 5
                          ? Colors.orange.shade700
                          : Colors.green.shade700,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  product.isSoldOut
                      ? loc.translate('bread_sold_out')
                      : loc
                          .translate('bread_stock_remaining')
                          .replaceAll('{n}', product.remaining.toString()),
                  style: const TextStyle(
                    fontSize: AppText.labelTiny,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ])),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    style: const TextStyle(
                        fontSize: AppText.bodySmall,
                        fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    product.isYopish
                        ? 'Ёпиш хизмати'
                        : product.isToy
                            ? 'Тўй нони'
                            : 'Тайёр',
                    style: TextStyle(
                      fontSize: AppText.labelTiny,
                      color: accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!product.isYopish && !product.isToy) ...[
                  const SizedBox(height: 2),
                  Text('${formatPrice(widget.price)} сўм',
                      style: TextStyle(
                          fontSize: AppText.labelSmall,
                          fontWeight: FontWeight.bold,
                          color: accentColor)),
                ],
                const SizedBox(height: 6),
                widget.count > 0
                    ? _counterRow(accentColor)
                    : _addButton(loc, accentColor, disabled: product.isSoldOut),
              ]),
        ),
      ]),
    );
  }

  Widget _imageWidget() {
    final trimmed = product.imageUrl.trim();
    final mem = decodeDataUrlImageBytes(trimmed);
    if (mem != null && mem.isNotEmpty) {
      return Image.memory(
        mem,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            Center(child: Text(product.emoji, style: const TextStyle(fontSize: 42))),
      );
    }
    final url = _networkImageUrl(trimmed);
    if (url != null) {
      return Image.network(
        url,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: product.isYopish ? _orange : _primary,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Center(
          child: Text(product.emoji, style: const TextStyle(fontSize: 42)),
        ),
      );
    }
    if (product.image.isNotEmpty) {
      return Image.asset(
        product.image,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Center(child: Text(product.emoji, style: const TextStyle(fontSize: 42))),
      );
    }
    return Center(child: Text(product.emoji, style: const TextStyle(fontSize: 42)));
  }

  /// `https://...` ёки `//host/...` — бошқа схемаларда `null` (эмодзи).
  static String? _networkImageUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return null;
    if (u.startsWith('//')) u = 'https:$u';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    return null;
  }

  Widget _counterRow(Color accent) {
    final canIncrement = !product.isReady ||
        product.totalStock <= 0 ||
        widget.count < product.remaining;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      GestureDetector(
        onTap: widget.onDecrement,
        child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200)),
            child: const Icon(Icons.remove, size: 14, color: Colors.red)),
      ),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('${widget.count}',
              style: TextStyle(
                  fontSize: AppText.titleMedium,
                  fontWeight: FontWeight.bold,
                  color: accent))),
      GestureDetector(
        onTap: canIncrement ? widget.onIncrement : null,
        child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
                color: canIncrement
                    ? accent.withOpacity(0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: canIncrement
                        ? accent.withOpacity(0.3)
                        : Colors.grey.shade300)),
            child: Icon(Icons.add,
                size: 14, color: canIncrement ? accent : Colors.grey)),
      ),
    ]);
  }

  Widget _addButton(AppLocalizations loc, Color accent,
      {bool disabled = false}) {
    return SizedBox(
      width: double.infinity,
      height: 30,
      child: ElevatedButton.icon(
        onPressed: disabled ? null : widget.onAdd,
        icon: Icon(disabled ? Icons.block : Icons.add, size: 14),
        label: Text(
            disabled
                ? loc.translate('bread_sold_out')
                : loc.translate('bread_add'),
            style: const TextStyle(fontSize: AppText.labelSmall)),
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade600,
          padding: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
