import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_shop_repository.dart';
import '../services/tv_storage_service.dart';

/// Эгаси товар расмларини 5 тагача қўшади / олиб ташлайди.
class TvShopItemPhotosScreen extends StatefulWidget {
  const TvShopItemPhotosScreen({super.key, required this.item});

  final TvShopItem item;

  @override
  State<TvShopItemPhotosScreen> createState() => _TvShopItemPhotosScreenState();
}

class _TvShopItemPhotosScreenState extends State<TvShopItemPhotosScreen> {
  final _picker = ImagePicker();
  final _storage = TvStorageService();
  final _repo = TvShopRepository();
  late List<String> _urls;
  final _newFiles = <XFile>[];
  bool _saving = false;

  int get _total => _urls.length + _newFiles.length;

  @override
  void initState() {
    super.initState();
    _urls = List<String>.from(widget.item.displayPhotos);
  }

  Future<void> _pick() async {
    final room = TvShopItem.maxPhotos - _total;
    if (room <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_shop_photos_max'))),
      );
      return;
    }
    final picked = await _picker.pickMultiImage(
      imageQuality: 88,
      limit: room,
    );
    if (picked.isEmpty) return;
    setState(() {
      _newFiles.addAll(picked.take(room));
    });
  }

  Future<void> _save() async {
    if (_total == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_shop_photo_required'))),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final uploaded = _newFiles.isEmpty
          ? const <String>[]
          : await _storage.uploadShopPhotos(
              ownerPhone: canonicalPhoneId(widget.item.ownerPhone),
              filePaths: _newFiles.map((f) => f.path).toList(),
            );
      final photos = TvShopItem.normalizePhotos(
        rawUrls: [..._urls, ...uploaded],
      );
      await _repo.updateItem(widget.item.id, {
        'photoUrl': photos.first,
        'photoUrls': photos,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[TvShopPhotos] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: Text(context.tr('tv_shop_photos_edit')),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.4,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.tr('save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          Text(
            context.tr('tv_shop_photos_hint'),
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$_total/${TvShopItem.maxPhotos}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < _urls.length; i++)
                _Thumb(
                  cover: i == 0 && _newFiles.isEmpty,
                  onRemove: _saving
                      ? null
                      : () => setState(() => _urls.removeAt(i)),
                  child: Image.network(_urls[i], fit: BoxFit.cover),
                ),
              for (var i = 0; i < _newFiles.length; i++)
                _Thumb(
                  cover: _urls.isEmpty && i == 0,
                  onRemove: _saving
                      ? null
                      : () => setState(() => _newFiles.removeAt(i)),
                  child: Image.file(
                    File(_newFiles[i].path),
                    fit: BoxFit.cover,
                  ),
                ),
              if (_total < TvShopItem.maxPhotos)
                GestureDetector(
                  onTap: _saving ? null : _pick,
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: Colors.grey.shade600),
                        const SizedBox(height: 4),
                        Text(
                          context.tr('tv_shop_photos_add'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.child,
    required this.cover,
    this.onRemove,
  });

  final Widget child;
  final bool cover;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(width: 108, height: 108, child: child),
        ),
        if (cover)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                context.tr('tv_shop_cover'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        Positioned(
          right: -4,
          top: -4,
          child: Material(
            color: Colors.black87,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const SizedBox(
                width: 26,
                height: 26,
                child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
