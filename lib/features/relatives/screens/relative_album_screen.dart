import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/relative_person.dart';
import '../../../models/relative_photo.dart';
import '../../../repositories/relatives_repository.dart';
import '../services/relative_photo_storage.dart';

/// 📷 Qarindosh fotoalbomi — bir qarindoshga bir nechta rasm.
class RelativeAlbumScreen extends StatefulWidget {
  const RelativeAlbumScreen({
    super.key,
    required this.userId,
    required this.person,
  });

  final String userId;
  final RelativePerson person;

  static const _accent = Color(0xFF6A4C93);

  @override
  State<RelativeAlbumScreen> createState() => _RelativeAlbumScreenState();
}

class _RelativeAlbumScreenState extends State<RelativeAlbumScreen> {
  final _repo = RelativesRepository();
  final _photo = RelativePhotoStorage();
  final _picker = ImagePicker();
  bool _uploading = false;

  Future<void> _addPhotos() async {
    final List<XFile> files = await _picker.pickMultiImage(imageQuality: 90);
    if (files.isEmpty) return;
    setState(() => _uploading = true);
    try {
      for (final f in files) {
        final res = await _photo.uploadPhoto(userId: widget.userId, image: f);
        await _repo.addAlbumPhoto(
          widget.userId,
          widget.person.id,
          RelativePhoto(id: '', url: res.url, storagePath: res.path),
        );
      }
    } catch (e) {
      _snack('Юклашда хатолик: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(RelativePhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Расмни ўчириш'),
        content: const Text('Бу расмни ўчирасизми?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Йўқ')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Ўчираман'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteAlbumPhoto(widget.userId, widget.person.id, photo.id);
    await _photo.deleteByUrl(photo.url);
  }

  void _openViewer(List<RelativePhoto> photos, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoViewer(
          photos: photos,
          initialIndex: index,
          onDelete: _delete,
        ),
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      appBar: AppBar(
        title: Text('📷 ${widget.person.fullName}'),
        backgroundColor: RelativeAlbumScreen._accent,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: RelativeAlbumScreen._accent,
        foregroundColor: Colors.white,
        onPressed: _uploading ? null : _addPhotos,
        icon: _uploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add_photo_alternate_outlined),
        label: Text(_uploading ? 'Юкланмоқда...' : 'Расм қўшиш'),
      ),
      body: StreamBuilder<List<RelativePhoto>>(
        stream: _repo.watchAlbum(widget.userId, widget.person.id),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final photos = snap.data ?? const <RelativePhoto>[];
          if (photos.isEmpty) {
            return _empty();
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: photos.length,
            itemBuilder: (_, i) {
              final ph = photos[i];
              return GestureDetector(
                onTap: () => _openViewer(photos, i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    ph.url,
                    fit: BoxFit.cover,
                    loadingBuilder: (c, child, prog) => prog == null
                        ? child
                        : Container(color: Colors.black12),
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.black12,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📷', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('Ҳали расм йўқ.\nПастдаги тугма орқали расм қўшинг.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.onDelete,
  });

  final List<RelativePhoto> photos;
  final int initialIndex;
  final Future<void> Function(RelativePhoto) onDelete;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _ctrl =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.photos.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final nav = Navigator.of(context);
              await widget.onDelete(widget.photos[_index]);
              nav.pop();
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.network(widget.photos[i].url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
