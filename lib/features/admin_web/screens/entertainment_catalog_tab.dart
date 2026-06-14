import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../../../models/entertainment_video.dart';
import '../../../repositories/entertainment_repository.dart';
import '../../entertainment/services/entertainment_storage.dart';

/// Admin — kino katalogi (B variant, 1-bosqich).
class EntertainmentCatalogTab extends StatefulWidget {
  const EntertainmentCatalogTab({super.key});

  @override
  State<EntertainmentCatalogTab> createState() => _EntertainmentCatalogTabState();
}

class _EntertainmentCatalogTabState extends State<EntertainmentCatalogTab> {
  final _storage = EntertainmentStorage();

  Future<void> _uploadVideo() async {
    final titleCtrl = TextEditingController();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    if (bytes.length > EntertainmentStorage.maxUploadBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Видео жуда катта (макс. '
              '${EntertainmentStorage.maxUploadBytes ~/ (1024 * 1024)} МБ).',
            ),
          ),
        );
      }
      return;
    }

    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Film nomi'),
        content: TextField(
          controller: titleCtrl,
          decoration: const InputDecoration(hintText: 'Masalan: Safar filmi 1'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Bekor')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, titleCtrl.text.trim()),
            child: const Text('Davom'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;

    try {
      final repo = context.read<EntertainmentRepository>();
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final path = 'entertainment/$id.mp4';
      final url = await _storage.uploadVideo(
        videoId: id,
        bytes: bytes,
      );
      await repo.createCatalogEntry(
        id: id,
        title: title,
        storagePath: path,
        downloadUrl: url,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video yuklandi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xato: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<EntertainmentRepository>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Katalog — haydovchilar tanlaydi, yo‘lovchi offline tomosha qiladi.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              FilledButton.icon(
                onPressed: _uploadVideo,
                icon: const Icon(Icons.upload_file),
                label: const Text('Video yuklash'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<EntertainmentVideo>>(
            stream: repo.watchCatalog(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snap.data!;
              if (list.isEmpty) {
                return const Center(child: Text('Katalog bo‘sh'));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final v = list[i];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        v.active ? Icons.movie : Icons.movie_outlined,
                        color: v.active ? AppColors.primary : Colors.grey,
                      ),
                      title: Text(v.title),
                      subtitle: Text(
                        '${v.storagePath}\n${v.durationLabel.isNotEmpty ? v.durationLabel : "MP4"}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      isThreeLine: true,
                      trailing: Switch(
                        value: v.active,
                        onChanged: (on) =>
                            repo.setCatalogActive(v.id, on),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
