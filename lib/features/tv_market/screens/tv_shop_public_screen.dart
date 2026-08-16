import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../models/tv_clip.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_clips_repository.dart';
import '../repositories/tv_shop_repository.dart';
import '../widgets/tv_shop_photo_gallery.dart';
import 'tv_market_feed_screen.dart';

/// Сотувчи дўкони — товар/хизмат карталари + қўнғироқ.
class TvShopPublicScreen extends StatefulWidget {
  const TvShopPublicScreen({
    super.key,
    required this.ownerPhone,
    this.highlightItemId = '',
  });

  final String ownerPhone;
  final String highlightItemId;

  @override
  State<TvShopPublicScreen> createState() => _TvShopPublicScreenState();
}

class _TvShopPublicScreenState extends State<TvShopPublicScreen> {
  final _shopRepo = TvShopRepository();
  final _clipsRepo = TvClipsRepository();
  TvShop? _shop;
  List<TvShopItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final shop = await _shopRepo.fetchShop(widget.ownerPhone);
      final items = await _shopRepo.fetchByOwner(widget.ownerPhone);
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _items = items.where((i) => i.isActive).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[TvShopPublic] $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _call() async {
    final ok = await callPhone(widget.ownerPhone);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_call_failed'))),
      );
    }
  }

  Future<void> _openClip(TvShopItem item) async {
    if (item.clipIds.isEmpty) return;
    final clips = await _clipsRepo.fetchByOwner(widget.ownerPhone);
    TvClip? clip;
    for (final id in item.clipIds) {
      final hit = clips.where((c) => c.id == id && c.isActive);
      if (hit.isNotEmpty) {
        clip = hit.first;
        break;
      }
    }
    if (clip == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvMarketFeedScreen(initialClip: clip),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _shop?.name.trim().isNotEmpty == true
        ? _shop!.name
        : context.tr('tv_shop_mine');
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: Text(name),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.4,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(
                    context.tr('tv_shop_empty'),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    final hi = item.id == widget.highlightItemId;
                    return _ShopItemCard(
                      item: item,
                      highlight: hi,
                      onVideo: item.hasVideo ? () => _openClip(item) : null,
                    );
                  },
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _call,
              icon: const Icon(Icons.call_rounded, size: 20),
              label: Text(
                context.tr('tv_shop_contact'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShopItemCard extends StatelessWidget {
  const _ShopItemCard({
    required this.item,
    required this.highlight,
    this.onVideo,
  });

  final TvShopItem item;
  final bool highlight;
  final VoidCallback? onVideo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: highlight ? 4 : 0,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlight
                ? const Color(0xFF00E676)
                : Colors.grey.shade200,
            width: highlight ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TvShopPhotoCarousel(
              urls: item.displayPhotos,
              height: 200,
              hasVideo: item.hasVideo,
              onVideo: onVideo,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatMoney(item.price),
                    style: const TextStyle(
                      color: Color(0xFF00A853),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.districtLabel,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
