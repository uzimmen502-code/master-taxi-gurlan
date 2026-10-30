import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../models/wholesale_product.dart';
import '../models/wholesale_seller.dart';
import '../repositories/wholesale_products_repository.dart';
import '../repositories/wholesale_stock_repository.dart';
import '../services/wholesale_storage_service.dart';
import '../services/wholesale_video_link.dart';
import '../utils/wholesale_labels.dart' show kWholesaleDefaultUnit;
import '../widgets/wholesale_field_error.dart';
import '../widgets/wholesale_pack_editor.dart';
import '../widgets/wholesale_tier_picker.dart' show kWholesaleTapSize;

/// Хитой бозори учун валюта танлови. Бўш қиймат — сўм (модел `currency`
/// бўш бўлса сўм деб қарайди), шунинг учун "сўм" чипи бўш сақланади.
class _CurrencyOption {
  const _CurrencyOption(this.value, this.labelKey);
  final String value;

  /// Матн калити (уч тилда): `currency_sum` ҳамма тилда «сўм» (иловадаги ягона ёзув).
  final String labelKey;
}

const _kCurrencies = <_CurrencyOption>[
  _CurrencyOption('', 'currency_sum'),
  _CurrencyOption('\$', 'wholesale_currency_usd'),
  _CurrencyOption('¥', 'wholesale_currency_cny'),
];

/// Маҳсулот қўшиш/таҳрирлаш — ном, тавсиф, нарх поғоналари, бирлик, расм(1-5).
/// Хитой бозорида қўшимча: валюта ва етказиш муддати.
class WholesaleProductFormScreen extends StatefulWidget {
  const WholesaleProductFormScreen({
    super.key,
    required this.seller,
    this.existing,
    this.market = WholesaleProduct.marketWholesale,
  });

  final WholesaleSeller seller;

  /// `null` — янги маҳсулот, акс ҳолда — таҳрирлаш.
  final WholesaleProduct? existing;

  /// Қайси бозорга қўшилаяпти — `wholesale` ёки `china`. Таҳрирлашда
  /// [existing] нинг бозори устун: Rules эгага маҳсулотни бошқа бозорга
  /// кўчиришга рухсат бермайди.
  final String market;

  @override
  State<WholesaleProductFormScreen> createState() =>
      _WholesaleProductFormScreenState();
}

class _WholesaleProductFormScreenState
    extends State<WholesaleProductFormScreen> {
  static const _maxImages = WholesaleProduct.maxImages;

  final _formKey = GlobalKey<FormState>();
  final _repo = WholesaleProductsRepository();
  final _storage = WholesaleStorageService();

  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _unitCtrl;

  /// Хитой бозори: етказиш муддати (кун) — ихтиёрий.
  late final TextEditingController _deliveryCtrl;

  /// Хитой бозори: нарх валютаси (бўш — сўм).
  String _currency = '';

  /// Қадоқлар (эга, 2026-10-31): ҳар бирининг нархи, вазни/ўлчами, қолдиғи
  /// ва ихтиёрий расми. Битта НОМСИЗ қадоқ — оддий (қадоқсиз) маҳсулот.
  final List<WholesalePackDraft> _packs = [];
  final _stockRepo = WholesaleStockRepository();

  final List<String> _existingImageUrls = [];
  final List<XFile> _newImages = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  /// Таҳрирлашда маҳсулотнинг ўз бозори, янгисида — экран узатгани.
  String get _market => widget.existing?.market ?? widget.market;

  bool get _isChina => _market == WholesaleProduct.marketChina;

  /// Нарх майдонларидаги валюта ёрлиғи.
  String get _currencyLabel =>
      _currency.trim().isEmpty ? context.tr('currency_sum') : _currency.trim();

  /// Бирлик майдони бўш бўлса кўрсатиладиган (ва базага `дона` деб ёзиладиган) бирлик.
  String get _unitText {
    final t = _unitCtrl.text.trim();
    return t.isEmpty ? context.tr('piece') : t;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    // Ўрнатилган «дона» майдонга ёзилмайди: бўш қолади, ҳинт тилга мос
    // кўрсатилади ва сақлашда `дона` ёзилади (эски мижозлар билан мос).
    _unitCtrl = TextEditingController(
      text: e == null || e.unit == kWholesaleDefaultUnit ? '' : e.unit,
    );
    _deliveryCtrl = TextEditingController(
      text: (e?.deliveryDays ?? 0) > 0 ? '${e!.deliveryDays}' : '',
    );
    _currency = e?.currency.trim() ?? '';
    if (e != null) {
      // Эски (қадоқсиз) маҳсулот — битта номсиз қадоқ: поғоналар МОҚ
      // чегарасига қараб энг мос майдонга тушади (1..9 / 10..49 / 50+).
      _packs.addAll(e.effectivePacks.map(WholesalePackDraft.fromPack));
      _existingImageUrls.addAll(e.imageUrls);
      _loadStock(e);
    } else {
      _packs.add(WholesalePackDraft(id: 'p1'));
    }
  }

  /// Таҳрирда сақланган қолдиқни майдонларга қўяди (фақат бўш майдонга —
  /// сотувчи ёзиб улгурган бўлса тегилмайди).
  Future<void> _loadStock(WholesaleProduct e) async {
    try {
      final s = await _stockRepo.fetch(e.id);
      if (!mounted) return;
      setState(() {
        for (final (i, p) in e.effectivePacks.indexed) {
          final q = s.of(p.id);
          if (q != null && i < _packs.length && _packs[i].stock.text.isEmpty) {
            _packs[i].stock.text = '$q';
          }
        }
      });
    } catch (err) {
      debugPrint('[Wholesale] load stock failed: $err');
    }
  }

  /// Битта номсиз қадоқ — оддий маҳсулот (эски кўриниш, `packs` йўқ).
  bool get _isSimple => _packs.length == 1 && _packs.first.label.text.trim().isEmpty;

  void _addPack() {
    if (_packs.length >= WholesalePack.maxPacks) return;
    setState(() => _packs.add(WholesalePackDraft(id: WholesalePack.nextId(_packs.map((p) => p.id)))));
  }

  void _removePack(int index) {
    if (_packs.length <= 1) return;
    setState(() => _packs.removeAt(index).dispose());
  }

  Future<void> _pickPackPhoto(WholesalePackDraft d) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null || !mounted) return;
    setState(() {
      d.newPhoto = x;
      d.removePhoto = false;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _unitCtrl.dispose();
    _deliveryCtrl.dispose();
    for (final p in _packs) {
      p.dispose();
    }
    super.dispose();
  }

  int get _totalImageCount => _existingImageUrls.length + _newImages.length;

  /// Бўлим остидаги хатолар ва скролл учун калитлар.
  bool _imagesErr = false;
  final _imagesKey = GlobalKey();
  final _titleKey = GlobalKey();
  final _tiersKey = GlobalKey();

  Future<void> _pickImages() async {
    final remaining = _maxImages - _totalImageCount;
    if (remaining <= 0) return;
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;
    setState(() {
      _newImages.addAll(picked.take(remaining));
      _imagesErr = false;
    });
  }

  void _removeExisting(int index) {
    setState(() => _existingImageUrls.removeAt(index));
  }

  void _removeNew(int index) {
    setState(() => _newImages.removeAt(index));
  }

  /// Ҳар бир қадоқни текширади ва хатоларни карточкага ёзади. Қайтаради:
  /// ҳаммаси тўғрими.
  bool _validatePacks() {
    final simple = _isSimple;
    var ok = true;
    for (final d in _packs) {
      d.labelErr = !simple && d.label.text.trim().isEmpty;
      d.tiersErr = d.collectTiers().isEmpty;
      d.stockErrKey = d.collectStock().error;
      if (d.labelErr || d.tiersErr || d.stockErrKey != null || d.collectShipping().error != null) {
        ok = false;
      }
    }
    return ok;
  }

  /// Қадоқ расмлари: янгиси юкланади, олиб ташлангани/алмашгани — Storage'дан ўчирилади.
  Future<({List<WholesalePack> packs, List<String> orphanPhotos})> _buildPacks() async {
    final out = <WholesalePack>[];
    final orphans = <String>[];
    for (final d in _packs) {
      var photo = d.removePhoto ? '' : d.existingPhotoUrl;
      if (d.newPhoto != null) {
        final up = await _storage.uploadImages(sellerId: widget.seller.phone, images: [d.newPhoto!]);
        if (up.isNotEmpty) photo = up.first;
      }
      if (d.existingPhotoUrl.isNotEmpty && photo != d.existingPhotoUrl) orphans.add(d.existingPhotoUrl);
      final s = d.collectShipping();
      out.add(WholesalePack(
        id: d.id,
        label: d.label.text.trim(),
        priceTiers: d.collectTiers(),
        unitWeightG: s.weightG,
        unitDims: s.dims,
        photoUrl: photo,
      ));
    }
    return (packs: out, orphanPhotos: orphans);
  }

  /// Киритилган қолдиқлар `{packId: qty}`. Оддий маҳсулотда — `default`.
  Map<String, int> _stockMap(bool simple) {
    final m = <String, int>{};
    for (final d in _packs) {
      final q = d.collectStock().qty;
      if (q != null) m[simple ? WholesalePack.defaultId : d.id] = q;
    }
    return m;
  }

  Future<void> _save() async {
    // Хатолар майдон/бўлим ёнида (SnackBar эмас): барчаси бирданига кўрсатилади
    // ва биринчи хатога скролл қилинади.
    final formOk = _formKey.currentState!.validate();
    final packsOk = _validatePacks();
    final imagesBad = _totalImageCount == 0;
    if (!formOk || !packsOk || imagesBad) {
      setState(() => _imagesErr = imagesBad);
      final first = imagesBad ? _imagesKey : (!formOk ? _titleKey : _tiersKey);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = first.currentContext;
        if (c != null) {
          Scrollable.ensureVisible(c,
              duration: const Duration(milliseconds: 200), alignment: 0.1);
        }
      });
      return;
    }
    final simple = _isSimple;
    setState(() => _saving = true);
    try {
      final uploaded = _newImages.isEmpty
          ? <String>[]
          : await _storage.uploadImages(
              sellerId: widget.seller.phone,
              images: _newImages,
            );
      final imageUrls = [..._existingImageUrls, ...uploaded];
      final built = await _buildPacks();
      final first = built.packs.first;
      final days = int.tryParse(_deliveryCtrl.text.trim());
      final product = WholesaleProduct(
        id: widget.existing?.id ?? '',
        sellerId: widget.seller.phone,
        sellerCompanyName: widget.seller.companyName,
        title: _titleCtrl.text.trim(),
        titleLower: _titleCtrl.text.trim().toLowerCase(),
        description: _descCtrl.text.trim(),
        // Оддий маҳсулот — ягона қадоқ маҳсулот майдонларига; қадоқлида
        // модел энг арзон қадоқдан нусха олади (орқага мослик).
        priceTiers: first.priceTiers,
        unit: _unitCtrl.text.trim().isEmpty
            ? kWholesaleDefaultUnit
            : _unitCtrl.text.trim(),
        imageUrls: imageUrls,
        market: _market,
        // Валюта ва етказиш муддати — фақат Хитой бозорида. Улгуржида
        // нарх ҳамиша сўмда, шунинг учун бўш қолдирилади.
        currency: _isChina ? _currency.trim() : '',
        deliveryDays: _isChina && days != null && days > 0 ? days : null,
        unitWeightG: first.unitWeightG,
        unitDims: first.unitDims,
        packs: simple ? const [] : built.packs,
      );
      String productId;
      if (_isEdit) {
        productId = widget.existing!.id;
        await _repo.ownerUpdate(productId, product);
        // Эга олиб ташлаган расмлар Storage'да эгасиз қолмасин
        // (2026-09-29). Аввал улар у ерда абадий қолиб кетар эди.
        final removed = [
          ...widget.existing!.imageUrls.where((u) => !_existingImageUrls.contains(u)),
          ...built.orphanPhotos,
        ];
        if (removed.isNotEmpty) {
          await _storage.deleteImages(removed);
        }
      } else {
        productId = await _repo.create(product);
      }
      // Қолдиқ — алоҳида, серверда (маҳсулот сақлангандан КЕЙИН: сервер
      // қадоқ ID'ларини маҳсулот ҳужжатидан текширади). Хато бўлса маҳсулот
      // сақланган бўлиб қолади — сотувчига алоҳида айтилади.
      var stockFailed = false;
      final stock = _stockMap(simple);
      if (stock.isNotEmpty) {
        try {
          await _stockRepo.setStock(productId, stock);
        } catch (e) {
          debugPrint('[Wholesale] set stock failed: $e');
          stockFailed = true;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: stockFailed ? AppColors.error : null,
          content: Text(context.tr(
            stockFailed
                ? 'wholesale_stock_save_failed'
                : (_isEdit ? 'wholesale_saved_updated' : 'wholesale_saved_sent'),
          )),
        ),
      );
      // Битта ихтиёрий видео (эга, 2026-10-31): видео бор бўлса таклиф йўқ.
      if ((widget.existing?.videoClipIds ?? const []).isEmpty) {
        await _offerVideo(productId);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[Wholesale] save product failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: AppColors.error,
            content: Text(context.tr('wholesale_action_failed'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Сақлагандан кейин — видеообзор/пуллик реклама қўшишни таклиф қилиш
  /// (талаб: «маҳсулот қўшишда»). Рад этилса ҳам кейин ⋮ менюдан қўшиш мумкин.
  Future<void> _offerVideo(String productId) async {
    if (productId.isEmpty) return;
    final wants = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('wholesale_video_dialog_title')),
        content: Text(
          context.tr('wholesale_video_dialog_body'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('wholesale_later')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('wholesale_add_video')),
          ),
        ],
      ),
    );
    if (wants != true || !mounted) return;
    try {
      final linked = await WholesaleVideoLink.publishAndLink(
        context,
        sellerPhone: widget.seller.phone,
        productId: productId,
      );
      if (!mounted || !linked) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('wholesale_video_linked'))),
      );
    } catch (e) {
      debugPrint('[Wholesale] link video failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            backgroundColor: AppColors.error,
            content: Text(context.tr('wholesale_action_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
          _isEdit ? 'wholesale_form_title_edit' : 'wholesale_new_product',
        )),
        // Сотувчи қайси бозорга қўшаётганини кўриб турсин — иккала
        // бозор битта коллекцияда, форма ҳам ўша форма.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                context.tr(
                    _isChina ? 'wholesale_title_china' : 'wholesale_title'),
                style: const TextStyle(
                  fontSize: AppText.labelSmall,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        // SingleChildScrollView (ListView эмас): барча бўлимлар қурилган бўлсин,
        // хатога скролл қилиш учун.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _imagesSection(),
            const SizedBox(height: 16),
            TextFormField(
              key: _titleKey,
              controller: _titleCtrl,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: context.tr('wholesale_field_name'),
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? context.tr('wholesale_min_3_chars')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              maxLength: 2000,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: context.tr('wholesale_field_desc'),
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? context.tr('wholesale_min_3_chars')
                  : null,
            ),
            if (_isChina) ...[
              const SizedBox(height: 16),
              _chinaSection(),
            ],
            const SizedBox(height: 16),
            KeyedSubtree(key: _tiersKey, child: _packsSection()),
            const SizedBox(height: 12),
            TextFormField(
              controller: _unitCtrl,
              // Поғона ёрлиқлари («1–9 дона» ва ҳ.к.) шу бирликка эргашади.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: context.tr('wholesale_field_unit'),
                hintText: context.tr('piece'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.tr(_isEdit ? 'save' : 'wholesale_submit')),
            ),
          ],
          ),
        ),
      ),
    );
  }

  /// Хитой бозорига хос майдонлар: валюта ва етказиш муддати.
  /// Иккаласи ҳам ихтиёрий — валюта танланмаса сўм, муддат киритилмаса
  /// карточкада кўрсатилмайди (`formatDelivery` бўш қайтаради).
  Widget _chinaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('wholesale_currency'),
            style: TextStyle(
                fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final c in _kCurrencies)
            ChoiceChip(
              label: Text(context.tr(c.labelKey)),
              selected: _currency.trim() == c.value,
              onSelected: (_) => setState(() => _currency = c.value),
            ),
        ]),
        const SizedBox(height: 12),
        TextFormField(
          controller: _deliveryCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: context.tr('wholesale_field_delivery_days'),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  /// Қадоқлар (эга, 2026-10-31): 1..5 карточка. Битта номсиз карточка —
  /// оддий маҳсулот (сотувчи учун форма аввалгидек содда қолади).
  Widget _packsSection() {
    final unit = _unitText;
    final showLabels = _packs.length > 1 || !_isSimple;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('wholesale_packs_title'),
            style: const TextStyle(
                fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          context.tr('wholesale_packs_help'),
          style: TextStyle(fontSize: AppText.bodySmall, color: AppColors.sectionMuted),
        ),
        const SizedBox(height: 10),
        for (final (i, d) in _packs.indexed)
          WholesalePackCard(
            draft: d,
            index: i,
            unitLabel: unit,
            currencyLabel: _currencyLabel,
            showLabel: showLabels,
            onChanged: () => setState(() {}),
            onPickPhoto: () => _pickPackPhoto(d),
            onRemove: _packs.length > 1 ? () => _removePack(i) : null,
          ),
        if (_packs.length < WholesalePack.maxPacks)
          OutlinedButton.icon(
            key: const ValueKey('wholesale-pack-add'),
            onPressed: _addPack,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(kWholesaleTapSize)),
            icon: const Icon(Icons.add),
            label: Text(context.tr('wholesale_pack_add')
                .replaceAll('{n}', '${_packs.length}')
                .replaceAll('{max}', '${WholesalePack.maxPacks}')),
          ),
      ],
    );
  }
  Widget _imagesSection() {
    return Column(
      key: _imagesKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            context
                .tr('wholesale_images_n')
                .replaceAll('{max}', '$_maxImages'),
            style: const TextStyle(
                fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < _existingImageUrls.length; i++)
            _imageThumb(
              child:
                  Image.network(_existingImageUrls[i], fit: BoxFit.contain),
              onRemove: () => _removeExisting(i),
            ),
          for (var i = 0; i < _newImages.length; i++)
            _imageThumb(
              child: _XFileImage(_newImages[i]),
              onRemove: () => _removeNew(i),
            ),
          if (_totalImageCount < _maxImages)
            Semantics(
              button: true,
              label: context.tr('wholesale_add_photo'),
              child: InkWell(
                onTap: _pickImages,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: _imagesErr ? AppColors.error : Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined),
                ),
              ),
            ),
        ]),
        if (_imagesErr) const WholesaleFieldError(textKey: 'wholesale_err_image_required'),
      ],
    );
  }

  Widget _imageThumb({
    required Widget child,
    required VoidCallback onRemove,
  }) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          // contain: расм четлари қирқилмайди (ега 2026-10-19); бўш жой — кулранг фон.
          child: ColoredBox(
            color: Colors.grey.shade200,
            child: SizedBox(
              width: 84,
              height: 84,
              child: child,
            ),
          ),
        ),
        // Кўринадиган доира кичик (22), лекин босиладиган майдон 48×48.
        Positioned(
          top: 0,
          right: 0,
          child: Semantics(
            button: true,
            label: context.tr('delete'),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const SizedBox(
                width: kWholesaleTapSize,
                height: kWholesaleTapSize,
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: EdgeInsets.all(2),
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _XFileImage extends StatelessWidget {
  const _XFileImage(this.file);
  final XFile file;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(color: Colors.grey.shade200);
        }
        return Image.memory(snap.data!, fit: BoxFit.contain);
      },
    );
  }
}
