import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../models/tv_clip.dart';
import '../services/tv_storage_service.dart';

/// TV Market — видео жойлаш экрани.
class TvPublishScreen extends StatefulWidget {
  const TvPublishScreen({super.key});

  @override
  State<TvPublishScreen> createState() => _TvPublishScreenState();
}

class _TvPublishScreenState extends State<TvPublishScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  final _picker = ImagePicker();
  final _storageService = TvStorageService();

  XFile? _videoFile;
  VideoPlayerController? _previewCtrl;
  String _category = 'product';
  bool _publishing = false;
  double _uploadProgress = 0;
  String _publishStage = '';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _previewCtrl?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo(ImageSource source) async {
    final file = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 60),
    );
    if (file == null) return;

    _previewCtrl?.dispose();
    final ctrl = VideoPlayerController.file(File(file.path));
    await ctrl.initialize();
    ctrl.setLooping(true);
    ctrl.play();

    setState(() {
      _videoFile = file;
      _previewCtrl = ctrl;
    });
  }

  void _showPickerSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videocam_rounded),
              title: Text(context.tr('tv_publish_camera')),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_rounded),
              title: Text(context.tr('tv_publish_gallery')),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    if (_videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_video_required'))),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auth required')),
      );
      return;
    }

    setState(() {
      _publishing = true;
      _uploadProgress = 0;
      _publishStage = context.tr('tv_publish_compressing');
    });

    try {
      final phone = user.phoneNumber ?? user.uid;
      final districtId = ServiceConfigHolder.districtId;
      final districtLabel = ServiceConfigHolder.districtLabel;

      final settingsSnap = await FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .get();
      final autoApprove =
          settingsSnap.data()?['tvAutoApprove'] == true;

      // 1. Видеони сиқиш (720p, medium)
      final compressed = await VideoCompress.compressVideo(
        _videoFile!.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      if (!mounted) return;
      final compressedPath = compressed?.file?.path ?? _videoFile!.path;

      // 2. Thumbnail олиш
      if (mounted) {
        setState(() => _publishStage = context.tr('tv_publish_thumbnail'));
      }
      Uint8List? thumbBytes;
      final thumbFile = await VideoCompress.getFileThumbnail(
        _videoFile!.path,
        quality: 75,
        position: -1,
      );
      if (thumbFile.existsSync()) {
        thumbBytes = await thumbFile.readAsBytes();
      }

      // 3. Видео юклаш
      if (mounted) {
        setState(() {
          _publishStage = context.tr('tv_publish_uploading');
          _uploadProgress = 0;
        });
      }
      final videoUrl = await _storageService.uploadVideo(
        ownerPhone: phone,
        filePath: compressedPath,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );

      // 4. Poster юклаш
      String posterUrl = '';
      if (thumbBytes != null && thumbBytes.isNotEmpty) {
        if (mounted) {
          setState(() => _publishStage = context.tr('tv_publish_poster'));
        }
        posterUrl = await _storageService.uploadPoster(
          ownerPhone: phone,
          bytes: thumbBytes,
        );
      }

      // 5. Firestore'га ёзиш
      final clip = TvClip(
        id: '',
        videoUrl: videoUrl,
        posterUrl: posterUrl,
        title: _titleCtrl.text.trim(),
        price: int.tryParse(_priceCtrl.text.trim()) ?? 0,
        districtId: districtId,
        districtLabel: districtLabel,
        ownerPhone: phone,
        ownerName: user.displayName ?? phone,
        category: _category,
        description: _descCtrl.text.trim(),
        status: autoApprove ? 'active' : 'pending',
      );

      await FirebaseFirestore.instance
          .collection('tv_clips')
          .add(clip.toMap());

      // Вақтинча кеш тозалаш
      await VideoCompress.deleteAllCache();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(autoApprove
              ? context.tr('tv_publish_success')
              : context.tr('tv_publish_pending')),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Хатолик: $e')),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(context.tr('tv_publish_title')),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Видео превью / танлаш
              GestureDetector(
                onTap: _publishing ? null : _showPickerSheet,
                child: Container(
                  height: 280,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _previewCtrl != null &&
                          _previewCtrl!.value.isInitialized
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Center(
                              child: AspectRatio(
                                aspectRatio:
                                    _previewCtrl!.value.aspectRatio,
                                child: VideoPlayer(_previewCtrl!),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: _showPickerSheet,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.edit,
                                      color: Colors.white, size: 18),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.video_call_rounded,
                                size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              context.tr('tv_publish_pick_video'),
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 20),

              // Ном
              TextFormField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('tv_publish_name'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Номни киритинг' : null,
              ),
              const SizedBox(height: 14),

              // Нарх
              TextFormField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('tv_publish_price'),
                  suffixText: 'сўм',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Тавсиф
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.tr('tv_publish_description'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Тури
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'product',
                    label: Text(context.tr('tv_publish_product')),
                    icon: const Icon(Icons.shopping_bag_outlined),
                  ),
                  ButtonSegment(
                    value: 'service',
                    label: Text(context.tr('tv_publish_service')),
                    icon: const Icon(Icons.build_outlined),
                  ),
                ],
                selected: {_category},
                onSelectionChanged: (v) =>
                    setState(() => _category = v.first),
              ),
              const SizedBox(height: 10),

              // Жойлашув
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ServiceConfigHolder.districtLabel.isNotEmpty
                            ? ServiceConfigHolder.districtLabel
                            : context.tr('tv_publish_no_location'),
                        style: TextStyle(
                          fontSize: 14,
                          color: ServiceConfigHolder
                                  .districtLabel.isNotEmpty
                              ? Colors.black87
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('tv_publish_location_hint'),
                style: TextStyle(
                    color: Colors.grey.shade500, fontSize: 12),
              ),
              const SizedBox(height: 24),

              // Юклаш прогресси
              if (_publishing) ...[
                LinearProgressIndicator(
                  value: _publishStage.contains('юклан') || _publishStage.contains('upload')
                      ? _uploadProgress
                      : null,
                  backgroundColor: Colors.grey.shade200,
                  color: const Color(0xFF00E676),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 8),
                Text(
                  _publishStage.isNotEmpty
                      ? '$_publishStage${_uploadProgress > 0 && _uploadProgress < 1 ? ' ${(_uploadProgress * 100).toInt()}%' : ''}'
                      : '${(_uploadProgress * 100).toInt()}%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Жойлаш тугмаси
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _publishing ? null : _publish,
                  icon: _publishing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.publish_rounded),
                  label: Text(
                    context.tr('tv_publish_submit'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
