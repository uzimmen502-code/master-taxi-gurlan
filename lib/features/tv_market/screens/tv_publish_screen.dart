import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_clip.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_clips_repository.dart';
import '../repositories/tv_shop_repository.dart';
import '../services/tv_clip_compress.dart';
import '../services/tv_clip_geo.dart';
import '../services/tv_owner_name.dart';
import '../services/tv_social.dart';
import '../services/tv_storage_service.dart';
import '../utils/tv_clip_search.dart';
import '../widgets/tv_clip_poster.dart';

/// TV Market — видео жойлаш экрани.
class TvPublishScreen extends StatefulWidget {
  const TvPublishScreen({
    super.key,
    this.attachItemId = '',
    this.editClip,
  });

  /// Мавжуд товар/хизматга яна ролик қўшиш.
  final String attachItemId;

  /// Берилса — жойлаш эмас, шу роликни таҳрирлаш.
  final TvClip? editClip;

  @override
  State<TvPublishScreen> createState() => _TvPublishScreenState();
}

class _TvPublishScreenState extends State<TvPublishScreen>
    with WidgetsBindingObserver {
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
  bool _openShop = false;
  final _socialNetworks = <String>{};
  String _attachItemId = '';
  final _productPhotos = <XFile>[];
  List<TvShopItem> _myItems = const [];
  final _shopRepo = TvShopRepository();
  String _districtPreview = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachItemId = widget.attachItemId;
    final edit = widget.editClip;
    if (edit != null) {
      _titleCtrl.text = edit.title;
      _priceCtrl.text = edit.price > 0 ? '${edit.price}' : '';
      _descCtrl.text = edit.description;
      _category = edit.category == 'service' ? 'service' : 'product';
    }
    unawaited(_loadShop());
  }

  Future<void> _loadShop() async {
    if (_isEdit) return;
    final prefs = await SharedPreferences.getInstance();
    final phone = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    if (phone.isEmpty) return;
    try {
      final exists = await _shopRepo.hasShop(phone);
      final items = exists ? await _shopRepo.fetchByOwner(phone) : const <TvShopItem>[];
      final geo = await TvClipGeo.resolveForPublisher(ownerPhone: phone);
      if (!mounted) return;
      setState(() {
        _districtPreview = geo.districtLabel;
        _myItems = items.where((i) => i.isActive).toList();
        if (exists) _openShop = true;
        if (_attachItemId.isNotEmpty) _openShop = true;
        if (_attachItemId.isNotEmpty) {
          for (final it in _myItems) {
            if (it.id == _attachItemId) {
              _titleCtrl.text = it.title;
              _priceCtrl.text = it.price > 0 ? '${it.price}' : '';
              _descCtrl.text = it.description;
              _category = it.kind;
              break;
            }
          }
        }
      });
    } catch (e) {
      debugPrint('[TvPublish] shop $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _previewCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.resumed) {
      ctrl.play();
    } else {
      ctrl.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _pickProductPhotos() async {
    final room = TvShopItem.maxPhotos - _productPhotos.length;
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
      _productPhotos.addAll(picked.take(room));
    });
  }

  bool get _isEdit => widget.editClip != null;

  Future<({String videoUrl, String posterUrl})> _uploadPickedVideo(
    String phone,
  ) async {
    setState(() {
      _publishStage = context.tr('tv_publish_compressing');
      _uploadProgress = 0;
    });
    final compressed = await TvClipCompress.forUpload(
      _videoFile!.path,
      onProgress: (p) {
        if (mounted) setState(() => _uploadProgress = p);
      },
    );
    if (!mounted) {
      throw StateError('unmounted');
    }
    if (compressed.trimmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_trimmed'))),
      );
    }
    setState(() => _publishStage = context.tr('tv_publish_thumbnail'));
    final thumbBytes = await TvClipCompress.thumbnailBytes(compressed.path);
    setState(() {
      _publishStage = context.tr('tv_publish_uploading');
      _uploadProgress = 0;
    });
    final videoUrl = await _storageService.uploadVideo(
      ownerPhone: phone,
      filePath: compressed.path,
      onProgress: (p) {
        if (mounted) setState(() => _uploadProgress = p);
      },
    );
    var posterUrl = '';
    if (thumbBytes != null && thumbBytes.isNotEmpty) {
      if (mounted) {
        setState(() => _publishStage = context.tr('tv_publish_poster'));
      }
      posterUrl = await _storageService.uploadPoster(
        ownerPhone: phone,
        bytes: thumbBytes,
      );
    }
    return (videoUrl: videoUrl, posterUrl: posterUrl);
  }

  Future<void> _saveEdit() async {
    if (!_formKey.currentState!.validate()) return;
    final clip = widget.editClip!;
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
      _publishStage = '';
    });

    try {
      final phone = canonicalPhoneId(user.phoneNumber ?? user.uid);
      var videoUrl = clip.videoUrl;
      var posterUrl = clip.posterUrl;
      if (_videoFile != null) {
        final uploaded = await _uploadPickedVideo(phone);
        videoUrl = uploaded.videoUrl;
        if (uploaded.posterUrl.isNotEmpty) posterUrl = uploaded.posterUrl;
      }

      final title = _titleCtrl.text.trim();
      final price = int.tryParse(_priceCtrl.text.trim()) ?? 0;
      final description = _descCtrl.text.trim();
      final tokens = TvClipSearch.buildTokens(
        title: title,
        description: description,
        districtLabel: clip.districtLabel,
        category: _category,
        ownerName: clip.ownerName,
        mfy: clip.mfy ?? '',
      );
      await TvClipsRepository().updateOwnClip(
        clipId: clip.id,
        title: title,
        price: price,
        description: description,
        category: _category,
        searchTokens: tokens,
        videoUrl: _videoFile != null ? videoUrl : null,
        posterUrl: _videoFile != null ? posterUrl : null,
      );
      if (clip.shopItemId.isNotEmpty) {
        try {
          await _shopRepo.updateItem(clip.shopItemId, {
            'title': title,
            'price': price,
            'description': description,
            'kind': _category,
          });
        } catch (e) {
          debugPrint('[TvPublish] shop item patch $e');
        }
      }
      if (_videoFile != null) {
        unawaited(TvStorageService().deleteClipFiles(
          videoUrl: clip.videoUrl,
          posterUrl: clip.posterUrl,
        ));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_saved'))),
      );
      Navigator.pop(
        context,
        clip.copyWith(
          title: title,
          price: price,
          description: description,
          category: _category,
          videoUrl: videoUrl,
          posterUrl: posterUrl,
          searchTokens: tokens,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_save_failed'))),
      );
      debugPrint('[TvPublish] save $e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _publish() async {
    if (widget.editClip != null) {
      await _saveEdit();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_video_required'))),
      );
      return;
    }

    final shopMode = _openShop || _attachItemId.isNotEmpty;
    if (shopMode && _attachItemId.isEmpty && _productPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_shop_photo_required'))),
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
      final phoneRaw = user.phoneNumber ?? user.uid;
      final phone = canonicalPhoneId(phoneRaw);
      final geo = await TvClipGeo.resolveForPublisher(ownerPhone: phone);
      final districtId = geo.districtId;
      final districtLabel = geo.districtLabel;

      final ownerName = await resolveLocalTvOwnerGivenName(phone: phone);
      final ownerDisplay = tvOwnerDisplayName(ownerName);

      final settingsSnap = await FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .get();
      final autoApprove =
          settingsSnap.data()?['tvAutoApprove'] == true;

      final uploaded = await _uploadPickedVideo(phone);
      if (!mounted) return;
      final videoUrl = uploaded.videoUrl;
      final posterUrl = uploaded.posterUrl;

      String shopItemId = _attachItemId;
      var clipPrice = int.tryParse(_priceCtrl.text.trim()) ?? 0;
      final shopMode = _openShop || _attachItemId.isNotEmpty;
      if (!mounted) return;

      if (shopMode) {
        if (mounted) {
          setState(() => _publishStage = context.tr('tv_publish_photo_uploading'));
        }
        await _shopRepo.ensureShop(
          ownerPhone: phone,
          name: ownerDisplay,
        );
        if (_attachItemId.isEmpty) {
          final photoUrls = await _storageService.uploadShopPhotos(
            ownerPhone: phone,
            filePaths: _productPhotos.map((f) => f.path).toList(),
          );
          shopItemId = await _shopRepo.createItem(
            TvShopItem(
              id: '',
              ownerPhone: phone,
              ownerName: ownerDisplay,
              title: _titleCtrl.text.trim(),
              price: clipPrice,
              photoUrl: photoUrls.isNotEmpty ? photoUrls.first : '',
              photoUrls: photoUrls,
              kind: _category,
              districtId: districtId,
              districtLabel: districtLabel,
              description: _descCtrl.text.trim(),
              socialConsent: _socialNetworks.isNotEmpty,
              status: autoApprove ? 'active' : 'pending',
            ),
          );
        } else {
          final existing = await _shopRepo.fetchItem(_attachItemId);
          if (existing != null && existing.price > 0) {
            clipPrice = existing.price;
          }
        }
      }

      // 5. Firestore'га ёзиш
      final clip = TvClip(
        id: '',
        videoUrl: videoUrl,
        posterUrl: posterUrl,
        title: _titleCtrl.text.trim(),
        price: clipPrice,
        districtId: districtId,
        districtLabel: districtLabel,
        ownerPhone: phone,
        ownerName: ownerDisplay,
        category: _category,
        description: _descCtrl.text.trim(),
        status: autoApprove ? 'active' : 'pending',
        shopItemId: shopItemId,
        socialConsent: _socialNetworks.isNotEmpty,
        socialNetworks: _socialNetworks.toList(),
        searchTokens: TvClipSearch.buildTokens(
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          districtLabel: districtLabel,
          category: _category,
          ownerName: ownerDisplay,
        ),
      );

      final clipRef = await FirebaseFirestore.instance
          .collection('tv_clips')
          .add(clip.toMap());
      if (shopItemId.isNotEmpty) {
        await _shopRepo.addClipToItem(
          itemId: shopItemId,
          clipId: clipRef.id,
        );
      }

      if (!mounted) return;
      final lines = <String>[
        context.tr(autoApprove ? 'tv_publish_success' : 'tv_publish_pending'),
      ];
      if (_socialNetworks.isNotEmpty) {
        lines.add(context.tr('tv_social_queued'));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lines.join('\n'))),
      );
      await VideoCompress.deleteAllCache();
      if (!mounted) return;
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
        leading: const BackButton(color: Colors.black87),
        title: Text(
          context.tr(_isEdit ? 'tv_publish_edit_title' : 'tv_publish_title'),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.black87),
        actionsIconTheme: const IconThemeData(color: Colors.black87),
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
                      : _isEdit
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                TvClipPoster(
                                  url: widget.editClip!.posterUrl,
                                ),
                                ColoredBox(
                                  color: Colors.black26,
                                  child: Center(
                                    child: Text(
                                      context.tr('tv_publish_replace_video'),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
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
                enabled: _isEdit || _attachItemId.isEmpty,
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
              const SizedBox(height: 16),

              if (!_isEdit) ...[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _openShop || _attachItemId.isNotEmpty,
                onChanged: _attachItemId.isNotEmpty
                    ? null
                    : (v) => setState(() {
                          _openShop = v;
                          if (!v) {
                            _attachItemId = '';
                            _productPhotos.clear();
                          }
                        }),
                title: Text(
                  context.tr('tv_shop_open'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(context.tr('tv_shop_open_hint')),
              ),

              if (_openShop || _attachItemId.isNotEmpty) ...[
                if (_myItems.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.tr('tv_shop_existing_item'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _attachItemId.isEmpty ? '' : _attachItemId,
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(context.tr('tv_shop_new_item')),
                          ),
                          for (final it in _myItems)
                            DropdownMenuItem(
                              value: it.id,
                              child: Text(
                                it.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: widget.attachItemId.isNotEmpty
                            ? null
                            : (v) {
                                setState(() {
                                  _attachItemId = v ?? '';
                                  if (_attachItemId.isNotEmpty) {
                                    final it = _myItems.firstWhere(
                                      (e) => e.id == _attachItemId,
                                    );
                                    _titleCtrl.text = it.title;
                                    _priceCtrl.text =
                                        it.price > 0 ? '${it.price}' : '';
                                    _descCtrl.text = it.description;
                                    _category = it.kind;
                                    _productPhotos.clear();
                                  }
                                });
                              },
                      ),
                    ),
                  ),
                ],
                if (_attachItemId.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.tr('tv_shop_photo'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('tv_shop_photos_hint'),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 108,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (var i = 0; i < _productPhotos.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.file(
                                    File(_productPhotos[i].path),
                                    width: 108,
                                    height: 108,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                if (i == 0)
                                  Positioned(
                                    left: 6,
                                    bottom: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
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
                                      onTap: _publishing
                                          ? null
                                          : () => setState(
                                                () => _productPhotos.removeAt(i),
                                              ),
                                      child: const SizedBox(
                                        width: 26,
                                        height: 26,
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_productPhotos.length < TvShopItem.maxPhotos)
                          GestureDetector(
                            onTap: _publishing ? null : _pickProductPhotos,
                            child: Container(
                              width: 108,
                              height: 108,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 32,
                                    color: Colors.grey.shade500,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_productPhotos.length}/${TvShopItem.maxPhotos}',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 8),
              Text(
                context.tr('tv_social_title'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('tv_social_hint'),
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in TvSocial.ordered)
                    FilterChip(
                      label: Text(context.tr(TvSocial.labelKey(id))),
                      selected: _socialNetworks.contains(id),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _socialNetworks.add(id);
                        } else {
                          _socialNetworks.remove(id);
                        }
                      }),
                    ),
                ],
              ),
              ],

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
                        _isEdit
                            ? (widget.editClip!.districtLabel.isNotEmpty
                                ? widget.editClip!.districtLabel
                                : context.tr('tv_publish_no_location'))
                            : (_districtPreview.isNotEmpty
                                ? _districtPreview
                                : context.tr('tv_publish_no_location')),
                        style: TextStyle(
                          fontSize: 14,
                          color: (_isEdit
                                  ? widget.editClip!.districtLabel
                                  : _districtPreview)
                              .isNotEmpty
                              ? Colors.black87
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isEdit) ...[
                const SizedBox(height: 6),
                Text(
                  context.tr('tv_publish_location_hint'),
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
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
                      : Icon(
                          _isEdit
                              ? Icons.save_rounded
                              : Icons.publish_rounded,
                        ),
                  label: Text(
                    context.tr(
                      _isEdit ? 'tv_publish_save' : 'tv_publish_submit',
                    ),
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
