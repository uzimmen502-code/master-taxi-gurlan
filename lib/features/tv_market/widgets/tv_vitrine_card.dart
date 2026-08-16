import 'package:flutter/material.dart';

import '../../../core/brand_labels.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../models/tv_clip.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_clips_repository.dart';
import '../screens/tv_market_feed_screen.dart';
import '../screens/tv_shop_public_screen.dart';

/// AVA расмий SKU ва сотувчи витринасини ажратиш.
class TvVitrineCard extends StatelessWidget {
  const TvVitrineCard({
    super.key,
    required this.item,
    this.official = false,
    this.onAddToCart,
  });

  final TvShopItem item;
  final bool official;
  final VoidCallback? onAddToCart;

  Future<void> _openVideo(BuildContext context) async {
    if (item.clipIds.isEmpty) return;
    final clips = await TvClipsRepository().fetchByOwner(item.ownerPhone);
    TvClip? clip;
    for (final id in item.clipIds) {
      final hit = clips.where((c) => c.id == id && c.isActive);
      if (hit.isNotEmpty) {
        clip = hit.first;
        break;
      }
    }
    if (clip == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TvMarketFeedScreen(initialClip: clip)),
    );
  }

  Future<void> _call(BuildContext context) async {
    final ok = await callPhone(item.ownerPhone);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_call_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sellerLabel = official
        ? BrandLabels.brand
        : (item.ownerName.trim().isEmpty
            ? context.tr('tv_vitrine_seller')
            : item.ownerName);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.hasVideo ? () => _openVideo(context) : null,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE6E8EE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.photoUrl.isEmpty
                        ? ColoredBox(
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image_outlined, size: 36),
                          )
                        : Image.network(item.photoUrl, fit: BoxFit.cover),
                    if (item.hasVideo)
                      const Align(
                        alignment: Alignment.center,
                        child: _PlayMark(),
                      ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _Pill(
                        text: official
                            ? context.tr('tv_vitrine_ava')
                            : sellerLabel,
                        color: official
                            ? const Color(0xFF00E5FF)
                            : Colors.black87,
                        fg: official ? Colors.black : Colors.white,
                      ),
                    ),
                    if (item.isBoosted)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: _Pill(
                          text: context.tr('tv_vitrine_ad'),
                          color: const Color(0xFFFF1744),
                          fg: Colors.white,
                        ),
                      ),
                    if (item.socialPosted)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: _Pill(
                          text: context.tr('tv_vitrine_social'),
                          color: const Color(0xFF1877F2),
                          fg: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMoney(item.price),
                      style: const TextStyle(
                        color: Color(0xFF00A853),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 34,
                            child: FilledButton(
                              onPressed: () => _call(context),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF00E676),
                                foregroundColor: Colors.black,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                context.tr('tv_shop_contact'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (official && onAddToCart != null) ...[
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 34,
                            height: 34,
                            child: IconButton.filled(
                              onPressed: onAddToCart,
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF00E5FF),
                                foregroundColor: Colors.black,
                              ),
                              icon: const Icon(
                                Icons.add_shopping_cart_rounded,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                        if (!official) ...[
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 34,
                            height: 34,
                            child: IconButton.outlined(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TvShopPublicScreen(
                                      ownerPhone: item.ownerPhone,
                                      highlightItemId: item.id,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.storefront_outlined,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayMark extends StatelessWidget {
  const _PlayMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white70),
      ),
      child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.color,
    required this.fg,
  });

  final String text;
  final Color color;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}
