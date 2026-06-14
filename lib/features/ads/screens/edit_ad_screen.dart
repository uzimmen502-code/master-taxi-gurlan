import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../models/ad_model.dart';
import '../repositories/ads_repository.dart';
import '../services/ads_storage_service.dart';

/// Edit existing cheap product ad.
class EditAdScreen extends StatefulWidget {
  const EditAdScreen({super.key, required this.ad});

  final AdModel ad;

  @override
  State<EditAdScreen> createState() => _EditAdScreenState();
}

class _EditAdScreenState extends State<EditAdScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _phoneCtrl;

  final List<String> _keptUrls = [];
  final List<XFile> _newImages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final ad = widget.ad;
    _titleCtrl = TextEditingController(text: ad.title);
    _priceCtrl = TextEditingController(text: '${ad.price}');
    _descCtrl = TextEditingController(text: ad.description);
    _phoneCtrl = TextEditingController(text: ad.phone);
    _keptUrls.addAll(ad.imageUrls);
  }

  int get _totalImages => _keptUrls.length + _newImages.length;

  Future<void> _pickImages() async {
    if (_totalImages >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Энг кўпи 5 та расм')),
      );
      return;
    }
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 85,
      limit: 5 - _totalImages,
    );
    if (picked.isEmpty) return;
    setState(() {
      _newImages.addAll(picked);
      while (_totalImages > 5) {
        _newImages.removeLast();
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_totalImages < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Камida 1 та расм қолсин'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final repo = context.read<AdsRepository>();
      final storage = context.read<AdsStorageService>();
      final ad = widget.ad;

      final removedUrls = ad.imageUrls.where((u) => !_keptUrls.contains(u)).toList();
      if (removedUrls.isNotEmpty) {
        await storage.deleteAdImages(
          ownerId: ad.ownerId,
          imageUrls: removedUrls,
        );
      }

      var urls = List<String>.from(_keptUrls);
      if (_newImages.isNotEmpty) {
        final uploaded = await storage.uploadImages(
          ownerId: ad.ownerId,
          images: _newImages,
        );
        urls = [...urls, ...uploaded];
      }

      final title = _titleCtrl.text.trim();
      await repo.updateAd(ad.id, {
        'title': title,
        if (title != ad.title) 'titleLower': title.toLowerCase(),
        'description': _descCtrl.text.trim(),
        'price': int.parse(_priceCtrl.text.trim()),
        'phone': _phoneCtrl.text.trim(),
        'imageUrls': urls,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сақланди')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Хатолик: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Таҳрирлаш'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._keptUrls.map(
                  (url) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: url,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _loading
                              ? null
                              : () => setState(() => _keptUrls.remove(url)),
                        ),
                      ),
                    ],
                  ),
                ),
                ...List.generate(_newImages.length, (i) {
                  final f = _newImages[i];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: kIsWeb
                            ? Image.network(
                                f.path,
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                              )
                            : Image.file(
                                File(f.path),
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                              ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _loading
                              ? null
                              : () => setState(() => _newImages.removeAt(i)),
                        ),
                      ),
                    ],
                  );
                }),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pickImages,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Расм'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Номи *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Номини киритинг' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Нархи (so\'m) *'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Нархни киритинг';
                if (int.tryParse(v.trim()) == null) return 'Фақат рақам';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Тавсиф *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Тавсифни киритинг' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Телефон *'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Телефонни киритинг';
                if (phoneDigits(v).length < 9) return 'Телефон нотўғри';
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Сақлаш'),
            ),
          ],
        ),
      ),
    );
  }
}
