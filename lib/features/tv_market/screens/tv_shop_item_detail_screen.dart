import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/phone_launcher.dart';
import '../models/tv_clip.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_clips_repository.dart';
import '../repositories/tv_shop_repository.dart';
import '../widgets/shop_unavailable_view.dart';
import '../widgets/tv_channel_contact_bar.dart';
import '../widgets/tv_shop_item_card.dart';
import 'tv_market_feed_screen.dart';

/// Харидор товар детал: зум галерея + қўнғироқ. Ўхшаш товарлар йўқ.
///
/// Очилганда маҳсулот ҳолати қайта ўқилади (эга қарори 2026-10-25: админ блоки барча кириш йўлларида): эски
/// рўйхат, видео ёки ҳавола орқали келинганда ҳам блокланган/ўчирилган маҳсулот кўрсатилмайди.
class TvShopItemDetailScreen extends StatefulWidget {
  const TvShopItemDetailScreen({
    super.key,
    required this.item,
    this.onOpenShop,
    this.loadLatest,
  });

  final TvShopItem item;
  final VoidCallback? onOpenShop;

  /// Тест учун алмаштирилади; бўлмаса `TvShopRepository().fetchItem` (битта ўқиш).
  final Future<TvShopItem?> Function(String itemId)? loadLatest;

  @override
  State<TvShopItemDetailScreen> createState() => _TvShopItemDetailScreenState();
}

class _TvShopItemDetailScreenState extends State<TvShopItemDetailScreen> {
  late TvShopItem _item = widget.item;
  late bool _available = widget.item.isActive;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final load = widget.loadLatest ?? TvShopRepository().fetchItem;
      final fresh = await load(widget.item.id);
      if (!mounted) return;
      setState(() {
        if (fresh == null) {
          _available = false;
        } else {
          _item = fresh;
          _available = fresh.isActive;
        }
      });
    } catch (e) {
      // Тармоқ хатоси: қўлдаги нусха кўрсатилади (рўйхатлар ҳам фақат фаолини беради).
      debugPrint('[TvShopItemDetail] refresh: $e');
    }
  }

  Future<void> _call(BuildContext context) async {
    final ok = await callPhone(_item.ownerPhone);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_call_failed'))),
      );
    }
  }

  Future<void> _openClip(BuildContext context) async {
    final item = _item;
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
    final item = _item;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        leading: const BackButton(color: Colors.black87),
        title: Text(_available ? item.title : '', maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.black87),
        actionsIconTheme: const IconThemeData(color: Colors.black87),
        elevation: 0.4,
        actions: [
          if (_available && widget.onOpenShop != null)
            IconButton(
              tooltip: context.tr('tv_shop_mine'),
              onPressed: widget.onOpenShop,
              icon: const Icon(Icons.storefront_outlined),
            ),
        ],
      ),
      body: !_available
          ? const ShopUnavailableView(textKey: 'product_unavailable')
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                TvShopItemCard(
                  item: item,
                  onVideo: item.hasVideo ? () => _openClip(context) : null,
                ),
              ],
            ),
      bottomNavigationBar: _available ? TvChannelContactBar(onCall: () => _call(context)) : null,
    );
  }
}
