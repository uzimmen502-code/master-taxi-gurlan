import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../models/tv_clip.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_clips_repository.dart';
import '../repositories/tv_public_profiles_repository.dart';
import '../repositories/tv_shop_repository.dart';
import '../utils/tv_highlight_order.dart';
import '../widgets/tv_channel_contact_bar.dart';
import '../widgets/tv_channel_header.dart';
import '../widgets/tv_shop_item_card.dart';
import 'tv_market_feed_screen.dart';

/// Sotuvchi ochiq vitrinasi — kanal boshi + mahsulot kartalari + qoʻngʻiroq.
class TvShopPublicScreen extends StatefulWidget {
  const TvShopPublicScreen({
    super.key,
    required this.ownerPhone,
    this.highlightItemId = '',
    this.ownerDisplayName = '',
    this.districtLabel = '',
  });

  final String ownerPhone;
  final String highlightItemId;
  final String ownerDisplayName;
  final String districtLabel;

  @override
  State<TvShopPublicScreen> createState() => _TvShopPublicScreenState();
}

class _TvShopPublicScreenState extends State<TvShopPublicScreen> {
  final _shopRepo = TvShopRepository();
  final _clipsRepo = TvClipsRepository();
  final _profilesRepo = TvPublicProfilesRepository();
  TvShop? _shop;
  List<TvShopItem> _items = const [];
  String _displayName = '';
  String _district = '';
  int _totalViewCount = 0;
  int _clipCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _displayName = tvOwnerDisplayName(widget.ownerDisplayName);
    _district = widget.districtLabel.trim();
    _load();
  }

  Future<void> _load() async {
    try {
      final shop = await _shopRepo.fetchShop(widget.ownerPhone);
      final items = await _shopRepo.fetchByOwner(widget.ownerPhone);
      final active = items.where((i) => i.isActive).toList();
      final sorted = tvOrderHighlightFirst(
        active,
        (i) => i.id == widget.highlightItemId,
      );
      if (_displayName.isEmpty) {
        final names = await _profilesRepo.fetchMany([widget.ownerPhone]);
        final id = canonicalPhoneId(widget.ownerPhone);
        final fromProfile = tvOwnerDisplayName(names[id] ?? '');
        final fromShop = tvOwnerDisplayName(shop?.name ?? '');
        _displayName = fromProfile.isNotEmpty ? fromProfile : fromShop;
      }
      if (_district.isEmpty && sorted.isNotEmpty) {
        _district = sorted.first.districtLabel.trim();
      }
      final totalViews =
          await _profilesRepo.fetchTotalViewCount(widget.ownerPhone);
      final ownerClips = await _clipsRepo.fetchByOwner(widget.ownerPhone);
      final clipCount = ownerClips.where((c) => c.isActive).length;
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _items = sorted;
        _totalViewCount = totalViews;
        _clipCount = clipCount;
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

  String get _appBarTitle {
    if (_displayName.isNotEmpty) return _displayName;
    final shopName = tvOwnerDisplayName(_shop?.name ?? '');
    if (shopName.isNotEmpty) return shopName;
    return context.tr('tv_shop_mine');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: Text(_appBarTitle),
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
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                  children: [
                    TvChannelHeader(
                      displayName: _displayName,
                      districtLabel: _district,
                      clipCount: _clipCount > 0 ? _clipCount : null,
                      totalViewCount: _totalViewCount,
                    ),
                    Text(
                      context.tr('tv_shop_vitrine'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      TvShopItemCard(
                        item: _items[i],
                        highlight: _items[i].id == widget.highlightItemId,
                        onVideo: _items[i].hasVideo
                            ? () => _openClip(_items[i])
                            : null,
                      ),
                    ],
                  ],
                ),
      bottomNavigationBar: TvChannelContactBar(onCall: _call),
    );
  }
}
