import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/phone_launcher.dart';
import '../models/tv_clip.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_clips_repository.dart';
import '../widgets/tv_channel_contact_bar.dart';
import '../widgets/tv_shop_item_card.dart';
import 'tv_market_feed_screen.dart';

/// Харидор товар детал: зум галерея + қўнғироқ. Ўхшаш товарлар йўқ.
class TvShopItemDetailScreen extends StatelessWidget {
  const TvShopItemDetailScreen({
    super.key,
    required this.item,
    this.onOpenShop,
  });

  final TvShopItem item;
  final VoidCallback? onOpenShop;

  Future<void> _call(BuildContext context) async {
    final ok = await callPhone(item.ownerPhone);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_call_failed'))),
      );
    }
  }

  Future<void> _openClip(BuildContext context) async {
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
      MaterialPageRoute(
        builder: (_) => TvMarketFeedScreen(initialClip: clip),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        leading: const BackButton(color: Colors.black87),
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.black87),
        actionsIconTheme: const IconThemeData(color: Colors.black87),
        elevation: 0.4,
        actions: [
          if (onOpenShop != null)
            IconButton(
              tooltip: context.tr('tv_shop_mine'),
              onPressed: onOpenShop,
              icon: const Icon(Icons.storefront_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          TvShopItemCard(
            item: item,
            onVideo: item.hasVideo ? () => _openClip(context) : null,
          ),
        ],
      ),
      bottomNavigationBar: TvChannelContactBar(onCall: () => _call(context)),
    );
  }
}
