import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/user_repository.dart';
import '../models/tv_clip.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_clips_repository.dart';
import '../repositories/tv_shop_repository.dart';
import '../services/tv_ad_service.dart';
import '../services/tv_clip_compress.dart';
import '../services/tv_clip_geo.dart';
import '../services/tv_owner_name.dart';
import '../services/tv_social.dart';
import '../services/tv_storage_service.dart';
import '../utils/tv_clip_search.dart';
import '../utils/tv_news_detector.dart';
import '../widgets/tv_ad_tier_picker.dart';
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
  /// Матн чегаралари — қидирув токенлари ихтиёрий узунликдаги матндан
  /// қурилмаслиги ва Firestore ҳужжати шишиб кетмаслиги учун.
  static const _titleMaxLen = 80;
  static const _descMaxLen = 500;

  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  final _picker = ImagePicker();
  final _storageService = TvStorageService();

  XFile? _videoFile;
  VideoPlayerController? _previewCtrl;
  String _category = 'product';
  /// `true` — эга Товар/Хизмат/Эълон/Янгилик сегментидан бирини ўзи
  /// босган (🟡8). Шунгача сарлавҳа/тавсифда янгилик калит сўзи топилса
  /// `_category` авто «Янгилик»га (ёки йўқолса «Товар»га) ўтиб туради —
  /// шунчаки таклиф, тасдиқ эмас.
  bool _categoryTouched = false;
  bool _publishing = false;
  double _uploadProgress = 0;
  String _publishStage = '';

  /// Прогресс аниқ фоиз кўрсатадими (compress/upload босқичлари).
  /// Аввал бу `_publishStage` матни ичидан «юклан»/«upload» сўзи
  /// қидириб аниқланарди — рус тилида ишламай қоларди.
  bool _progressDeterminate = false;
  bool _openShop = false;
  final _socialNetworks = <String>{};
  String _attachItemId = '';
  final _productPhotos = <XFile>[];
  List<TvShopItem> _myItems = const [];
  final _shopRepo = TvShopRepository();
  String _districtPreview = '';

  String _adTier = tvAdTiers.first;
  int _adDurationDays = tvAdDurationOptions.first;
  String _adScope = tvAdScopes.first;
  Map<String, Map<int, int>> _adPricing = {
    for (final e in tvAdTierPricingDefault.entries) e.key: Map.of(e.value),
  };
  Map<String, num> _adScopeMultiplier = Map.of(tvAdScopeMultiplierDefault);
  int _walletBalance = 0;
  StreamSubscription<int>? _balanceSub;
  String _adIdempotencyKey = '';
  bool _showPhone = true;

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
      // `ad` / `news` категорияси таҳрирда ўзгармайди — аввал улар
      // «product»га айлантириб юбориларди (пуллик реклама ўз тарифини,
      // янгилик эса ўз лентасини йўқотарди).
      _category = _categoryLocked
          ? edit.category
          : (edit.category == 'service' ? 'service' : 'product');
      _showPhone = edit.showPhone;
      // Таҳрирда сегмент қулф — авто-таклиф ишламасин.
      _categoryTouched = true;
    }
    _titleCtrl.addListener(_suggestCategoryFromText);
    _descCtrl.addListener(_suggestCategoryFromText);
    unawaited(_loadShop());
    unawaited(_loadAdContext());
  }

  /// Сарлавҳа/тавсифда янгилик калит сўзи топилса — сегментни «Янгилик»га
  /// таклиф қилади; топилмаса «Товар»га қайтаради. Фақат эга ҳали
  /// сегментни ўзи танламаган ва дўкон/маҳсулот банд қилмаган пайтда
  /// (🟡8 — таклиф, эганинг ўз танлови устидан ёзилмайди).
  void _suggestCategoryFromText() {
    if (_isEdit || _categoryTouched || _category == 'ad') return;
    if (_openShop || _attachItemId.isNotEmpty) return;
    final looksNews =
        tvLooksLikeNews(_titleCtrl.text.trim(), _descCtrl.text.trim());
    final suggested = looksNews ? 'news' : 'product';
    if (_category != suggested) setState(() => _category = suggested);
  }

  Future<void> _loadAdContext() async {
    _adIdempotencyKey = const Uuid().v4();
    final results = await Future.wait([
      TvAdService.loadPricing(),
      TvAdService.loadScopeMultiplier(),
    ]);
    if (mounted) {
      setState(() {
        _adPricing = results[0] as Map<String, Map<int, int>>;
        _adScopeMultiplier = results[1] as Map<String, num>;
      });
    }
    final prefs = await SharedPreferences.getInstance();
    final phone = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    if (phone.isEmpty) return;
    // Баланс — жонли обуна (аввал `.first` билан бир марта ўқиларди:
    // бошқа экранда ҳамённи тўлдириб қайтганда эскирган қиймат
    // «Жойлаш» тугмасини блоклаб турарди).
    _balanceSub = UserRepository().watchBonusBalance(phone).listen(
      (balance) {
        if (mounted) setState(() => _walletBalance = balance);
      },
      onError: (Object e) => debugPrint('[TvPublish] wallet $e'),
    );
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
    unawaited(_balanceSub?.cancel());
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

  /// `ad`/`news` — таҳрирда категория ўзгартирилмайди (сегмент ҳам
  /// кўрсатилмайди): реклама тарифи ва янгилик лентаси сақланиб қолсин.
  bool get _categoryLocked {
    final c = widget.editClip?.category;
    return c == 'ad' || c == 'news';
  }

  int get _adSelectedPrice {
    final base = _adPricing[_adTier]?[_adDurationDays] ??
        tvAdTierPricingDefault[_adTier]?[_adDurationDays] ??
        0;
    final mult = _adScopeMultiplier[_adScope] ??
        tvAdScopeMultiplierDefault[_adScope] ??
        1;
    return (base * mult).round();
  }

  bool get _adInsufficientBalance {
    if (_category != 'ad' || _isEdit) return false;
    return _adSelectedPrice > 0 && _walletBalance < _adSelectedPrice;
  }

  Future<({String videoUrl, String posterUrl})> _uploadPickedVideo(
    String phone,
  ) async {
    setState(() {
      _publishStage = context.tr('tv_publish_compressing');
      _uploadProgress = 0;
      _progressDeterminate = true;
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
    if (compressed.oversized) {
      throw const TvClipTooLargeException();
    }
    final tooLong =
        await TvClipCompress.checkPostCompressDuration(compressed.path);
    if (!mounted) {
      throw StateError('unmounted');
    }
    if (tooLong) {
      throw const TvClipTooLongException();
    }
    if (compressed.trimmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_trimmed'))),
      );
    }
    setState(() {
      _publishStage = context.tr('tv_publish_thumbnail');
      _progressDeterminate = false;
    });
    final thumbBytes = await TvClipCompress.thumbnailBytes(compressed.path);
    setState(() {
      _publishStage = context.tr('tv_publish_uploading');
      _uploadProgress = 0;
      _progressDeterminate = true;
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
        setState(() {
          _publishStage = context.tr('tv_publish_poster');
          _progressDeterminate = false;
        });
      }
      posterUrl = await _storageService.uploadPoster(
        ownerPhone: phone,
        bytes: thumbBytes,
      );
    }
    return (videoUrl: videoUrl, posterUrl: posterUrl);
  }

  Future<void> _saveEdit() async {
    if (!_formKey.currentState!.validate()) {
      // Bug fix: ilgari bu yerda hech qanday ko'rinadigan reaksiya bo'lmasdi
      // — foydalanuvchi tugmani bossa, forma validatsiyasi jim muvaffaqiyatsiz
      // tugagach (mas. nom bo'sh), ekranda faqat kichik qizil matn chiqardi,
      // uni ko'rmasa "hech narsa bo'lmadi" deb o'ylashi mumkin edi.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_fill_required'))),
      );
      return;
    }
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

    var newVideoUrl = '';
    var newPosterUrl = '';
    var saved = false;
    try {
      final phone = canonicalPhoneId(user.phoneNumber ?? user.uid);
      var videoUrl = clip.videoUrl;
      var posterUrl = clip.posterUrl;
      if (_videoFile != null) {
        final uploaded = await _uploadPickedVideo(phone);
        videoUrl = uploaded.videoUrl;
        if (uploaded.posterUrl.isNotEmpty) posterUrl = uploaded.posterUrl;
        newVideoUrl = uploaded.videoUrl;
        newPosterUrl = uploaded.posterUrl;
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
        showPhone: _showPhone,
        videoUrl: _videoFile != null ? videoUrl : null,
        posterUrl: _videoFile != null ? posterUrl : null,
      );
      saved = true;
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
          showPhone: _showPhone,
        ),
      );
    } on TvClipTooLargeException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_too_large'))),
      );
    } on TvClipTooLongException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_too_long'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_save_failed'))),
      );
      debugPrint('[TvPublish] save $e');
    } finally {
      // Сақлаш йиқилса — янги юкланган файл «етим» қолмасин (эски
      // видео эса жойида қолади, чунки ёзув ўзгармаган).
      if (!saved && newVideoUrl.isNotEmpty) {
        unawaited(TvStorageService().deleteClipFiles(
          videoUrl: newVideoUrl,
          posterUrl: newPosterUrl,
        ));
      }
      if (mounted) {
        setState(() {
          _publishing = false;
          _progressDeterminate = false;
        });
      }
    }
  }

  Future<void> _publish() async {
    if (widget.editClip != null) {
      await _saveEdit();
      return;
    }
    if (!_formKey.currentState!.validate()) {
      // Bug fix: xuddi shu sabab — jim validatsiya muvaffaqiyatsizligi
      // "tugma bosilganda hech narsa bo'lmadi" deb ko'rinardi.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_fill_required'))),
      );
      return;
    }
    if (_videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_video_required'))),
      );
      return;
    }

    // «Эълон» — дўкон/витрина оқимидан мустақил. Аввал дўкони бор
    // фойдаланувчида `_openShop` авто-`true` бўлиб қолар ва эълон
    // жойлашда «камида 1 та расм» хатоси чиқарарди (расм UI'си эса
    // эълон режимида умуман кўрсатилмайди).
    final isAd = _category == 'ad';
    // «Янгилик» энди эга ўзи танлайдиган очиқ сегмент (🟡8) — авто-калит
    // сўз бўйича таклиф қилинади, лекин якуний манба шу ерда `_category`.
    final isNews = _category == 'news';
    final title = _titleCtrl.text.trim();
    final description = _descCtrl.text.trim();

    final wantsShopItem = _attachItemId.isNotEmpty || _productPhotos.isNotEmpty;
    final shopMode =
        !isAd && !isNews && (_openShop || _attachItemId.isNotEmpty);
    if (shopMode && !wantsShopItem) {
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

    // Хатолик юз берса Storage'да «етим» файл қолмаслиги учун — юкланган
    // URL'лар шу ерда сақланади ва `catch`да ўчирилади.
    var uploadedVideoUrl = '';
    var uploadedPosterUrl = '';
    var completed = false;
    try {
      final phoneRaw = user.phoneNumber ?? user.uid;
      final phone = canonicalPhoneId(phoneRaw);
      final geo = await TvClipGeo.resolveForPublisher(ownerPhone: phone);
      final districtId = geo.districtId;
      final districtLabel = geo.districtLabel;

      final ownerName = await resolveLocalTvOwnerGivenName(phone: phone);
      final ownerDisplay = tvOwnerDisplayName(ownerName);

      final uploaded = await _uploadPickedVideo(phone);
      if (!mounted) return;
      final videoUrl = uploaded.videoUrl;
      final posterUrl = uploaded.posterUrl;
      uploadedVideoUrl = videoUrl;
      uploadedPosterUrl = posterUrl;

      if (isAd) {
        setState(() {
          _publishStage = context.tr('tv_ad_publishing');
          _progressDeterminate = false;
        });
        // Реклама модерациядан ўтмайди — CF тўлов заҳоти `active` қилиб
        // яратади (🔴1/3 қарори). `scope`/`regionId` — CF'да нархни қайта
        // текшириш ва feed'да «вилоят»/«республика» бирлаштириш учун.
        final result = await TvAdService.publishTvAd(
          idempotencyKey: _adIdempotencyKey,
          videoUrl: videoUrl,
          posterUrl: posterUrl,
          title: title,
          price: int.tryParse(_priceCtrl.text.trim()) ?? 0,
          districtId: districtId,
          districtLabel: districtLabel,
          ownerName: ownerDisplay,
          description: description,
          durationDays: _adDurationDays,
          tier: _adTier,
          scope: _adScope,
          regionId: geo.regionId,
          showPhone: _showPhone,
          searchTokens: TvClipSearch.buildTokens(
            title: title,
            description: description,
            districtLabel: districtLabel,
            category: 'ad',
            ownerName: ownerDisplay,
          ),
        );
        completed = true;
        if (!mounted) return;
        final paid = (result['price'] as num?)?.toInt() ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              paid > 0
                  ? context
                      .tr('tv_ad_published_paid')
                      .replaceAll('{price}', formatMoney(paid))
                  : context.tr('tv_ad_published_free'),
            ),
          ),
        );
        await VideoCompress.deleteAllCache();
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      // `product` / `service` / авто-`news` йўли.
      final settingsSnap = await FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .get();
      final autoApprove = settingsSnap.data()?['tvAutoApprove'] == true;

      String shopItemId = _attachItemId;
      var clipPrice = int.tryParse(_priceCtrl.text.trim()) ?? 0;
      if (!mounted) return;

      if (shopMode) {
        setState(() => _publishStage = context.tr('tv_publish_photo_uploading'));
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
              title: title,
              price: clipPrice,
              photoUrl: photoUrls.isNotEmpty ? photoUrls.first : '',
              photoUrls: photoUrls,
              kind: _category,
              districtId: districtId,
              districtLabel: districtLabel,
              description: description,
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
        title: title,
        price: clipPrice,
        districtId: districtId,
        districtLabel: districtLabel,
        ownerPhone: phone,
        ownerName: ownerDisplay,
        category: _category,
        expiresAt: isNews ? DateTime.now().add(const Duration(hours: 48)) : null,
        description: description,
        status: autoApprove ? 'active' : 'pending',
        showPhone: _showPhone,
        shopItemId: shopItemId,
        socialConsent: _socialNetworks.isNotEmpty,
        socialNetworks: _socialNetworks.toList(),
        searchTokens: TvClipSearch.buildTokens(
          title: title,
          description: description,
          districtLabel: districtLabel,
          category: _category,
          ownerName: ownerDisplay,
        ),
      );

      final clipRef = await FirebaseFirestore.instance
          .collection('tv_clips')
          .add(clip.toMap());
      completed = true;
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
      if (isNews) {
        lines.add(context.tr('tv_publish_marked_news'));
      }
      if (_socialNetworks.isNotEmpty) {
        lines.add(context.tr('tv_social_queued'));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lines.join('\n'))),
      );
      await VideoCompress.deleteAllCache();
      if (!mounted) return;
      Navigator.pop(context, true);
    } on TvClipTooLargeException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_too_large'))),
      );
    } on TvClipTooLongException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_publish_too_long'))),
      );
    } on FirebaseFunctionsException catch (e) {
      final msg = e.code == 'failed-precondition' &&
              e.message == 'insufficient_balance'
          ? (mounted ? context.tr('tv_ad_insufficient_balance') : '')
          : 'Хатолик: ${e.message ?? e.code}';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Хатолик: $e')),
      );
    } finally {
      // Клип яратилмаган бўлса — юкланган видео/постер Storage'да
      // «етим» қолмасин (айниқса пуллик эълонда: баланс етмаслиги
      // айнан юклашдан кейин маълум бўлади).
      if (!completed && uploadedVideoUrl.isNotEmpty) {
        unawaited(TvStorageService().deleteClipFiles(
          videoUrl: uploadedVideoUrl,
          posterUrl: uploadedPosterUrl,
        ));
      }
      if (mounted) {
        setState(() {
          _publishing = false;
          _progressDeterminate = false;
        });
      }
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
              _VideoPreviewCard(
                controller: _previewCtrl,
                editPosterUrl: _isEdit ? widget.editClip!.posterUrl : null,
                onPick: _publishing ? null : _showPickerSheet,
              ),
              const SizedBox(height: 20),
              ..._fields(context),
              const SizedBox(height: 10),
              _LocationCard(
                label: _isEdit ? widget.editClip!.districtLabel : _districtPreview,
                showHint: !_isEdit,
              ),
              const SizedBox(height: 20),
              // Тур танлаш ва унга боғлиқ созламалар (тариф пикери ёки
              // дўкон/ижтимоий тармоқлар) энг охирида — «Тасдиқлаш»дан
              // тўғридан-тўғри олдин: эга умумий маълумотни (ном/нарх/
              // тавсиф/жойлашув) аввал тўлдиради, кейин турни танлайди.
              if (!_categoryLocked) ...[
                _categorySelector(context),
                const SizedBox(height: 16),
              ],
              if (!_isEdit && _category == 'ad') ...[
                TvAdTierPicker(
                  selectedTier: _adTier,
                  selectedDays: _adDurationDays,
                  pricing: _adPricing,
                  walletBalance: _walletBalance,
                  enabled: !_publishing,
                  onTierChanged: (t) => setState(() => _adTier = t),
                  onDaysChanged: (d) => setState(() => _adDurationDays = d),
                  selectedScope: _adScope,
                  scopeMultiplier: _adScopeMultiplier,
                  districtLabel: _districtPreview,
                  onScopeChanged: (s) => setState(() => _adScope = s),
                ),
                const SizedBox(height: 16),
              ],
              if (!_isEdit && _category != 'ad') ...[
                // Дўкон/маҳсулот — «Янгилик»га тегишли эмас (48 соатда
                // ўзи ўчади, витринага боғланмайди).
                if (_category != 'news') ..._shopSection(context),
                _SocialPicker(
                  selected: _socialNetworks,
                  onToggle: (id, on) => setState(
                    () => on ? _socialNetworks.add(id) : _socialNetworks.remove(id),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (_publishing) ...[
                _PublishProgress(
                  determinate: _progressDeterminate,
                  progress: _uploadProgress,
                  stage: _publishStage,
                ),
                const SizedBox(height: 16),
              ],
              _SubmitButton(
                isEdit: _isEdit,
                busy: _publishing,
                enabled: !_publishing && !_adInsufficientBalance,
                onPressed: _publish,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ном / нарх / тавсиф / телефонни кўрсатиш — контроллерларга боғлиқ
  /// бўлгани учун State ичида қолади.
  List<Widget> _fields(BuildContext context) => [
        TextFormField(
          controller: _titleCtrl,
          maxLength: _titleMaxLen,
          decoration: InputDecoration(
            labelText: context.tr('tv_publish_name'),
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: (v) => (v ?? '').trim().isEmpty
              ? context.tr('tv_publish_name_required')
              : null,
        ),
        const SizedBox(height: 14),
        // Эълон режимида бу МАҲСУЛОТ нархи (реклама нархи тариф×муддатдан
        // келади), шунинг учун ёрлиқ аниқлаштирилади.
        TextFormField(
          controller: _priceCtrl,
          keyboardType: TextInputType.number,
          enabled: _isEdit || _attachItemId.isEmpty,
          maxLength: 12,
          decoration: InputDecoration(
            labelText: context.tr(
              _category == 'ad' ? 'tv_publish_price_product' : 'tv_publish_price',
            ),
            suffixText: 'сўм',
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _descCtrl,
          maxLines: 3,
          maxLength: _descMaxLen,
          decoration: InputDecoration(
            labelText: context.tr('tv_publish_description'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 14),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _showPhone,
          onChanged: (v) => setState(() => _showPhone = v),
          title: Text(
            context.tr('tv_publish_show_phone'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          subtitle: Text(
            context.tr('tv_publish_show_phone_hint'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 8),
      ];

  /// Тури — `ad`/`news` таҳририда ўзгартирилмайди. «Янгилик» фақат янги
  /// жойлашда танланади (🟡8) — авто-таклиф қилинади, лекин эга босса
  /// шу танлов қотиб қолади (_categoryTouched).
  ///
  /// 4-сегмент (иконка билан) торроқ телефонларда, айниқса рус тилида,
  /// сўз ўртасидан бўлиниб кетарди («Тов-ар»). Иконкалар олиб ташланди
  /// ва матн кичрайтирилди — тор экранда ҳам 1 қаторда сиғади.
  Widget _categorySelector(BuildContext context) => SegmentedButton<String>(
        // Танланган сегментдаги ✓ белгиси (showSelectedIcon) ортиқча жой
        // ейди — фон ранги (яшил тонланиш) танловни аллақачон кўрсатади.
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        segments: [
          ButtonSegment(
            value: 'product',
            label: Text(context.tr('tv_publish_product')),
          ),
          ButtonSegment(
            value: 'service',
            label: Text(context.tr('tv_publish_service')),
          ),
          if (!_isEdit)
            ButtonSegment(
              value: 'ad',
              label: Text(context.tr('tv_publish_ad')),
            ),
          if (!_isEdit)
            ButtonSegment(
              value: 'news',
              label: Text(context.tr('tv_publish_news')),
            ),
        ],
        selected: {_category},
        onSelectionChanged: (v) => setState(() {
          _category = v.first;
          _categoryTouched = true;
        }),
      );

  /// «Дўкон очиш» блоки: мавжуд товарни танлаш ёки янги товар расмлари.
  List<Widget> _shopSection(BuildContext context) {
    final shopOn = _openShop || _attachItemId.isNotEmpty;
    return [
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: shopOn,
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
      if (shopOn) ...[
        if (_myItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            context.tr('tv_shop_existing_item'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _attachItemId,
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(context.tr('tv_shop_new_item')),
                  ),
                  for (final it in _myItems)
                    DropdownMenuItem(
                      value: it.id,
                      child: Text(it.title, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged:
                    widget.attachItemId.isNotEmpty ? null : _onExistingItemPicked,
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
          _ProductPhotoStrip(
            photos: _productPhotos,
            enabled: !_publishing,
            onAdd: _pickProductPhotos,
            onRemove: (i) => setState(() => _productPhotos.removeAt(i)),
          ),
        ],
      ],
      const SizedBox(height: 8),
    ];
  }

  /// Мавжуд товар танланганда — форма шу товар маълумотлари билан тўлади.
  void _onExistingItemPicked(String? id) {
    setState(() {
      _attachItemId = id ?? '';
      if (_attachItemId.isEmpty) return;
      final it = _myItems.firstWhere((e) => e.id == _attachItemId);
      _titleCtrl.text = it.title;
      _priceCtrl.text = it.price > 0 ? '${it.price}' : '';
      _descCtrl.text = it.description;
      _category = it.kind;
      _productPhotos.clear();
    });
  }
}

/// Танланган видео превьюси; таҳрирда — эски постер «алмаштириш» ёзуви билан.
class _VideoPreviewCard extends StatelessWidget {
  const _VideoPreviewCard({
    required this.controller,
    required this.editPosterUrl,
    required this.onPick,
  });

  final VideoPlayerController? controller;
  final String? editPosterUrl;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    final ready = ctrl != null && ctrl.value.isInitialized;
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 280,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        clipBehavior: Clip.antiAlias,
        child: ready
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: ctrl.value.aspectRatio,
                      child: VideoPlayer(ctrl),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
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
                ],
              )
            : editPosterUrl != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      TvClipPoster(url: editPosterUrl!),
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
    );
  }
}

/// Товар расмлари тасмаси — биринчиси муқова.
class _ProductPhotoStrip extends StatelessWidget {
  const _ProductPhotoStrip({
    required this.photos,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final List<XFile> photos;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < photos.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      File(photos[i].path),
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
                            horizontal: 7, vertical: 3),
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
                        onTap: enabled ? () => onRemove(i) : null,
                        child: const SizedBox(
                          width: 26,
                          height: 26,
                          child: Icon(Icons.close_rounded,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (photos.length < TvShopItem.maxPhotos)
            GestureDetector(
              onTap: enabled ? onAdd : null,
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
                    Icon(Icons.add_photo_alternate_outlined,
                        size: 32, color: Colors.grey.shade500),
                    const SizedBox(height: 4),
                    Text(
                      '${photos.length}/${TvShopItem.maxPhotos}',
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
    );
  }
}

/// Роликни AVA расмий ижтимоий тармоқларига ҳам юбориш танлови.
class _SocialPicker extends StatelessWidget {
  const _SocialPicker({required this.selected, required this.onToggle});

  final Set<String> selected;
  final void Function(String id, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                selected: selected.contains(id),
                onSelected: (on) => onToggle(id, on),
              ),
          ],
        ),
      ],
    );
  }
}

/// Ролик қайси ҳудудга бириктирилиши.
class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.label, required this.showHint});

  final String label;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final has = label.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on, color: Colors.grey, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  has ? label : context.tr('tv_publish_no_location'),
                  style: TextStyle(
                    fontSize: 14,
                    color: has ? Colors.black87 : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showHint) ...[
          const SizedBox(height: 6),
          Text(
            context.tr('tv_publish_location_hint'),
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Юклаш прогресси — сиқиш босқичида фоиз номаълум (indeterminate).
class _PublishProgress extends StatelessWidget {
  const _PublishProgress({
    required this.determinate,
    required this.progress,
    required this.stage,
  });

  final bool determinate;
  final double progress;
  final String stage;

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).toInt();
    final showPct = progress > 0 && progress < 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: determinate ? progress : null,
          backgroundColor: Colors.grey.shade200,
          color: const Color(0xFF00E676),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 8),
        Text(
          stage.isNotEmpty ? '$stage${showPct ? ' $pct%' : ''}' : '$pct%',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.isEdit,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final bool isEdit;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(isEdit ? Icons.save_rounded : Icons.publish_rounded),
        label: Text(
          context.tr(isEdit ? 'tv_publish_save' : 'tv_publish_submit'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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
    );
  }
}

