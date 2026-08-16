import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_shop_repository.dart';
import 'tv_publish_screen.dart';
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
  List<TvShopItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _repo.fetchByOwner(widget.ownerPhone);
      if (!mounted) return;
      setState(() {
        _items = items;
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
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: item.photoUrl.isEmpty
                                ? ColoredBox(
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.image_outlined),
                                  )
                                : Image.network(
                                    item.photoUrl,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${formatMoney(item.price)} · ${item.clipIds.length}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: IconButton(
                          tooltip: context.tr('tv_shop_add_clip'),
                          onPressed: () => _openPublish(attachItemId: item.id),
                          icon: const Icon(Icons.videocam_outlined),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
