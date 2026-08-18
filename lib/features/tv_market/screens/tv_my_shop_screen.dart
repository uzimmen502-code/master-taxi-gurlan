import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_clip.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_public_profiles_repository.dart';
import '../repositories/tv_shop_repository.dart';
import '../widgets/tv_channel_header.dart';
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

class _TvMyShopScreenState extends State<TvMyShopScreen> {
  final _repo = TvShopRepository();
  final _profilesRepo = TvPublicProfilesRepository();
  List<TvShopItem> _items = const [];
  String _displayName = '';
  String _district = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final shop = await _repo.fetchShop(widget.ownerPhone);
      final items = await _repo.fetchByOwner(widget.ownerPhone);
      final names = await _profilesRepo.fetchMany([widget.ownerPhone]);
      final id = canonicalPhoneId(widget.ownerPhone);
      final fromProfile = tvOwnerDisplayName(names[id] ?? '');
      final fromShop = tvOwnerDisplayName(shop?.name ?? '');
      final displayName =
          fromProfile.isNotEmpty ? fromProfile : fromShop;
      var district = '';
      if (items.isNotEmpty) {
        district = items.first.districtLabel.trim();
      }
      if (!mounted) return;
      setState(() {
        _items = items;
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPublish(),
        backgroundColor: const Color(0xFF00E676),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          context.tr('tv_shop_add_item'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      context.tr('tv_shop_empty'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                  children: [
                    if (_displayName.isNotEmpty)
                      TvChannelHeader(
                        displayName: _displayName,
                        districtLabel: _district,
                      ),
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                          onTap: () async {
                            final item = _items[i];
                            final ok = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    TvShopItemPhotosScreen(item: item),
                              ),
                            );
                            if (ok == true && mounted) await _load();
                          },
                          contentPadding:
                              const EdgeInsets.fromLTRB(10, 8, 8, 8),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _items[i].coverPhotoUrl.isEmpty
                                      ? ColoredBox(
                                          color: Colors.grey.shade200,
                                          child: const Icon(
                                            Icons.image_outlined,
                                          ),
                                        )
                                      : Image.network(
                                          _items[i].coverPhotoUrl,
                                          fit: BoxFit.cover,
                                        ),
                                  if (_items[i].displayPhotos.length > 1)
                                    Align(
                                      alignment: Alignment.bottomRight,
                                      child: Container(
                                        margin: const EdgeInsets.all(3),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${_items[i].displayPhotos.length}',
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
                          title: Text(
                            _items[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            _items[i].hasPrice
                                ? '${formatMoney(_items[i].price)} · ${_items[i].clipIds.length}'
                                : '${_items[i].clipIds.length}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: IconButton(
                            tooltip: context.tr('tv_shop_add_clip'),
                            onPressed: () =>
                                _openPublish(attachItemId: _items[i].id),
                            icon: const Icon(Icons.videocam_outlined),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}
