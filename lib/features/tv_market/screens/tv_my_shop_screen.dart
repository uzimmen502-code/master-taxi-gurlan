import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_clip.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_clips_repository.dart';
import '../repositories/tv_public_profiles_repository.dart';
import '../repositories/tv_shop_repository.dart';
import '../services/tv_clip_delete.dart';
import '../widgets/tv_channel_header.dart';
import '../widgets/tv_shop_photo_gallery.dart';
import '../../ads/screens/cheap_products_screen.dart';
import 'tv_publish_screen.dart';
import 'tv_shop_item_photos_screen.dart';
import 'tv_shop_public_screen.dart';

/// Эгасининг мини-дўкони — товар/нарх/видео таҳрири.
class TvMyShopScreen extends StatefulWidget {
  const TvMyShopScreen({super.key, required this.ownerPhone});

  final String ownerPhone;

  @override
  State<TvMyShopScreen> createState() => _TvMyShopScreenState();
}

class _TvMyShopScreenState extends State<TvMyShopScreen>
    with SingleTickerProviderStateMixin {
  final _shopRepo = TvShopRepository();
  final _clipsRepo = TvClipsRepository();
  final _profilesRepo = TvPublicProfilesRepository();
  late final TabController _tabController;
  List<TvShopItem> _items = const [];
  List<TvClip> _clips = const [];
  String _displayName = '';
  String _district = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final shop = await _shopRepo.fetchShop(widget.ownerPhone);
      final items = await _shopRepo.fetchByOwner(widget.ownerPhone);
      final clips = await _clipsRepo.fetchByOwner(widget.ownerPhone);
      final names = await _profilesRepo.fetchMany([widget.ownerPhone]);
      final id = canonicalPhoneId(widget.ownerPhone);
      final fromProfile = tvOwnerDisplayName(names[id] ?? '');
      final fromShop = tvOwnerDisplayName(shop?.name ?? '');
      final displayName =
          fromProfile.isNotEmpty ? fromProfile : fromShop;
      var district = '';
      if (items.isNotEmpty) {
        district = items.first.districtLabel.trim();
      } else if (clips.isNotEmpty) {
        district = clips.first.districtLabel.trim();
      }
      if (!mounted) return;
      setState(() {
        _items = items.where((i) => i.isActive).toList(growable: false);
        _clips = clips;
        _displayName = displayName;
        _district = district;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[TvMyShop] $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPublish({String attachItemId = ''}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TvPublishScreen(attachItemId: attachItemId),
      ),
    );
    if (ok == true && mounted) await _load();
  }

  Widget _buildItemsTab() {
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            context.tr('tv_my_shop_empty_items'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        if (_displayName.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: TvChannelHeader(
                displayName: _displayName,
                districtLabel: _district,
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 96),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.58,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = _items[index];
                return _OwnerManageCard(
                  title: item.title,
                  imageUrl: item.coverPhotoUrl,
                  subtitle: item.hasPrice ? formatMoney(item.price) : '',
                  badge: item.displayPhotos.length > 1
                      ? '${item.displayPhotos.length}'
                      : '',
                  onOpen: () => _openItemPhotos(item),
                  onEdit: () => _openItemPhotos(item),
                  onDelete: () => _deleteItem(item),
                );
              },
              childCount: _items.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClipsTab() {
    if (_clips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            context.tr('tv_my_shop_empty_clips'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        if (_displayName.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: TvChannelHeader(
                displayName: _displayName,
                districtLabel: _district,
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 96),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.58,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final clip = _clips[index];
                return _OwnerManageCard(
                  title: clip.title.isEmpty ? context.tr('tv_my_shop_tab_clips') : clip.title,
                  imageUrl: clip.posterUrl,
                  subtitle: clip.viewCount > 0 ? '${clip.viewCount}' : '',
                  isVideo: true,
                  onOpen: () => _openClipEdit(clip),
                  onEdit: () => _openClipEdit(clip),
                  onDelete: () => _deleteClip(clip),
                );
              },
              childCount: _clips.length,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openItemPhotos(TvShopItem item) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TvShopItemPhotosScreen(item: item),
      ),
    );
    if (ok == true && mounted) await _load();
  }

  Future<void> _openClipEdit(TvClip clip) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TvPublishScreen(editClip: clip),
      ),
    );
    if (ok == true && mounted) await _load();
  }

  Future<void> _deleteItem(TvShopItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('tv_shop_delete_confirm_title')),
        content: Text(context.tr('tv_shop_delete_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.tr('tv_shop_delete_item'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _shopRepo.deleteItem(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_shop_delete_success'))),
      );
      await _load();
    } catch (e) {
      debugPrint('[TvMyShop] delete item: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_delete_failed'))),
      );
    }
  }

  Future<void> _deleteClip(TvClip clip) async {
    try {
      final ok = await confirmDeleteTvClip(context, clip);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('tv_market_delete_done'))),
        );
        await _load();
      }
    } catch (e) {
      debugPrint('[TvMyShop] delete clip: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_delete_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: Text(context.tr('tv_shop_mine')),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.4,
        actions: [
          IconButton(
            tooltip: context.tr('tv_shop_to_market'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CheapProductsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.storefront_outlined),
          ),
          IconButton(
            tooltip: context.tr('tv_shop_preview'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      TvShopPublicScreen(ownerPhone: widget.ownerPhone),
                ),
              );
            },
            icon: const Icon(Icons.visibility_outlined),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black87,
          unselectedLabelColor: Colors.black54,
          indicatorColor: const Color(0xFF00E676),
          indicatorWeight: 3,
          tabs: [
            Tab(text: context.tr('tv_my_shop_tab_items')),
            Tab(text: context.tr('tv_my_shop_tab_clips')),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          final isItems = _tabController.index == 0;
          return FloatingActionButton.extended(
            onPressed: () => _openPublish(),
            backgroundColor: const Color(0xFF00E676),
            foregroundColor: Colors.black,
            icon: Icon(isItems ? Icons.add_rounded : Icons.videocam_rounded),
            label: Text(
              context.tr(isItems ? 'tv_shop_add_item' : 'tv_shop_add_clip'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          );
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildItemsTab(),
                _buildClipsTab(),
              ],
            ),
    );
  }
}

class _OwnerManageCard extends StatelessWidget {
  const _OwnerManageCard({
    required this.title,
    required this.imageUrl,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    this.subtitle = '',
    this.badge = '',
    this.isVideo = false,
  });

  final String title;
  final String imageUrl;
  final String subtitle;
  final String badge;
  final bool isVideo;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  imageUrl.isEmpty
                      ? ColoredBox(
                          color: Colors.grey.shade200,
                          child: Icon(
                            isVideo
                                ? Icons.videocam_outlined
                                : Icons.image_outlined,
                            size: 40,
                            color: Colors.black38,
                          ),
                        )
                      : TvShopNetworkImage(url: imageUrl, fit: BoxFit.cover),
                  if (isVideo)
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  if (badge.isNotEmpty)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
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
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF00A853),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onEdit,
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 36),
                        ),
                        child: Text(
                          context.tr('tv_market_edit'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Color(0xFFE53935)),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 36),
                        ),
                        child: Text(
                          context.tr('tv_market_delete'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

