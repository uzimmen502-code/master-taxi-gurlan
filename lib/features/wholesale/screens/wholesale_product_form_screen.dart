import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../models/wholesale_product.dart';
import '../models/wholesale_seller.dart';
import '../repositories/wholesale_products_repository.dart';
import '../services/wholesale_storage_service.dart';
import '../services/wholesale_video_link.dart';

/// Тайёр нарх поғонаси — қатъий МОҚ чегараси (1 / 10 / 50) ва кўринадиган
/// диапазон ёрлиғи. Нарх тўлдириш ихтиёрий (эга қарори, 2026-09-24):
/// фақат тўлдирилган поғоналар сақланади.
class _FixedTier {
  const _FixedTier(this.minQty, this.rangeLabel);
  final int minQty;
  final String rangeLabel;
}

const _kFixedTiers = <_FixedTier>[
  _FixedTier(1, '1–9'),
  _FixedTier(10, '10–49'),
  _FixedTier(50, '50+'),
];

/// Хитой бозори учун валюта танлови. Бўш қиймат — сўм (модел `currency`
/// бўш бўлса сўм деб қарайди), шунинг учун "сўм" чипи бўш сақланади.
class _CurrencyOption {
  const _CurrencyOption(this.value, this.label);
  final String value;
  final String label;
}

const _kCurrencies = <_CurrencyOption>[
  _CurrencyOption('', 'сўм'),
  _CurrencyOption('\$', '\$ доллар'),
  _CurrencyOption('¥', '¥ юань'),
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

  /// Етказиш учун (У1): бир дона вазни (кг матни) ва ўлчами (см).
  late final TextEditingController _weightCtrl;
  late final TextEditingController _dimLCtrl;
  late final TextEditingController _dimWCtrl;
  late final TextEditingController _dimHCtrl;

  /// Ҳар бир тайёр поғона учун нарх контроллери (тартиби [_kFixedTiers]га мос).
  late final List<TextEditingController> _priceCtrls;

  final List<String> _existingImageUrls = [];
  final List<XFile> _newImages = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  /// Таҳрирлашда маҳсулотнинг ўз бозори, янгисида — экран узатгани.
  String get _market => widget.existing?.market ?? widget.market;

  bool get _isChina => _market == WholesaleProduct.marketChina;

  /// Нарх майдонларидаги валюта ёрлиғи.
  String get _currencyLabel =>
      _currency.trim().isEmpty ? 'сўм' : _currency.trim();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _unitCtrl = TextEditingController(text: e?.unit ?? 'дона');
    _deliveryCtrl = TextEditingController(
      text: (e?.deliveryDays ?? 0) > 0 ? '${e!.deliveryDays}' : '',
    );
    _currency = e?.currency.trim() ?? '';
    _weightCtrl = TextEditingController(text: weightKgFieldText(e?.unitWeightG ?? 0));
    _dimLCtrl = TextEditingController(text: e?.unitDims == null ? '' : '${e!.unitDims!.l}');
    _dimWCtrl = TextEditingController(text: e?.unitDims == null ? '' : '${e!.unitDims!.w}');
    _dimHCtrl = TextEditingController(text: e?.unitDims == null ? '' : '${e!.unitDims!.h}');
    _priceCtrls =
        List.generate(_kFixedTiers.length, (_) => TextEditingController());
    if (e != null) {
      // Мавжуд поғоналарни уч тайёр майдонга жойлаш: МОҚ чегарасига қараб
      // энг мос майдонга (1..9 → 0, 10..49 → 1, 50+ → 2). Эски ностандарт
      // маълумот бўлса ҳам йиқилмайди — энг яқин майдонга тушади.
      for (final t in e.priceTiers) {
        final idx = t.minQty >= 50 ? 2 : (t.minQty >= 10 ? 1 : 0);
        _priceCtrls[idx].text = '${t.price}';
      }
      _existingImageUrls.addAll(e.imageUrls);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _unitCtrl.dispose();
    _deliveryCtrl.dispose();
    _weightCtrl.dispose();
    _dimLCtrl.dispose();
    _dimWCtrl.dispose();
    _dimHCtrl.dispose();
    for (final c in _priceCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  /// Вазн/ўлчам майдонларини ўқийди. Қайтаради: (`weightG`, `dims`) ёки
  /// хато калити. Иккаласи ҳам ихтиёрий; ўлчам — учаласи бирга ёки бўш;
  /// ўлчам бор, вазн йўқ — мумкин эмас (ҳажмий вазн ёлғиз маъносиз).
  ({int? weightG, ShippingDims? dims, String? error}) _collectShipping() {
    final wRaw = _weightCtrl.text.trim();
    int? weightG;
    if (wRaw.isNotEmpty) {
      weightG = parseWeightKgToGrams(wRaw);
      if (weightG == null) return (weightG: null, dims: null, error: 'wholesale_err_weight_invalid');
    }
    final raws = [_dimLCtrl.text.trim(), _dimWCtrl.text.trim(), _dimHCtrl.text.trim()];
    final filled = raws.where((s) => s.isNotEmpty).length;
    ShippingDims? dims;
    if (filled == 3) {
      final l = int.tryParse(raws[0]);
      final w = int.tryParse(raws[1]);
      final h = int.tryParse(raws[2]);
      if (l == null || w == null || h == null) {
        return (weightG: null, dims: null, error: 'wholesale_err_dims_invalid');
      }
      dims = ShippingDims(l: l, w: w, h: h);
      if (!dims.isValid) return (weightG: null, dims: null, error: 'wholesale_err_dims_invalid');
    } else if (filled != 0) {
      return (weightG: null, dims: null, error: 'wholesale_err_dims_invalid');
    }
    if (dims != null && weightG == null) {
      return (weightG: null, dims: null, error: 'wholesale_err_weight_invalid');
    }
    return (weightG: weightG, dims: dims, error: null);
  }

  /// Тўлдирилган поғоналарни йиғади (тўлдириш ихтиёрий). Бўш майдон ўтказиб
  /// юборилади; ҳеч бири тўлдирилмаса — бўш рўйхат (сақлаш блокланади).
  List<WholesalePriceTier> _collectTiers() {
    final tiers = <WholesalePriceTier>[];
    for (var i = 0; i < _kFixedTiers.length; i++) {
      final raw = _priceCtrls[i].text.trim();
      if (raw.isEmpty) continue;
      final price = int.tryParse(raw);
      if (price == null || price <= 0) continue;
      tiers.add(WholesalePriceTier(minQty: _kFixedTiers[i].minQty, price: price));
    }
    return sortWholesalePriceTiers(tiers);
  }

  int get _totalImageCount => _existingImageUrls.length + _newImages.length;

  Future<void> _pickImages() async {
    final remaining = _maxImages - _totalImageCount;
    if (remaining <= 0) return;
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;
    setState(() {
      _newImages.addAll(picked.take(remaining));
    });
  }

  void _removeExisting(int index) {
    setState(() => _existingImageUrls.removeAt(index));
  }

  void _removeNew(int index) {
    setState(() => _newImages.removeAt(index));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final tiers = _collectTiers();
    if (tiers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('wholesale_err_tier_required')),
        ),
      );
      return;
    }
    if (_totalImageCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.tr('wholesale_err_image_required'))),
      );
      return;
    }
    final shipping = _collectShipping();
    if (shipping.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr(shipping.error!))),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final uploaded = _newImages.isEmpty
          ? <String>[]
          : await _storage.uploadImages(
              sellerId: widget.seller.phone,
              images: _newImages,
            );
      final imageUrls = [..._existingImageUrls, ...uploaded];
      final days = int.tryParse(_deliveryCtrl.text.trim());
      final product = WholesaleProduct(
        id: widget.existing?.id ?? '',
        sellerId: widget.seller.phone,
        sellerCompanyName: widget.seller.companyName,
        title: _titleCtrl.text.trim(),
        titleLower: _titleCtrl.text.trim().toLowerCase(),
        description: _descCtrl.text.trim(),
        priceTiers: tiers,
        unit: _unitCtrl.text.trim().isEmpty ? 'дона' : _unitCtrl.text.trim(),
        imageUrls: imageUrls,
        market: _market,
        // Валюта ва етказиш муддати — фақат Хитой бозорида. Улгуржида
        // нарх ҳамиша сўмда, шунинг учун бўш қолдирилади.
        currency: _isChina ? _currency.trim() : '',
        deliveryDays: _isChina && days != null && days > 0 ? days : null,
        unitWeightG: shipping.weightG,
        unitDims: shipping.dims,
      );
      String productId;
      if (_isEdit) {
        productId = widget.existing!.id;
        await _repo.ownerUpdate(productId, product);
        // Эга олиб ташлаган расмлар Storage'да эгасиз қолмасин
        // (2026-09-29). Аввал улар у ерда абадий қолиб кетар эди.
        final removed = widget.existing!.imageUrls
            .where((u) => !_existingImageUrls.contains(u))
            .toList(growable: false);
        if (removed.isNotEmpty) {
          await _storage.deleteImages(removed);
        }
      } else {
        productId = await _repo.create(product);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr(
            _isEdit ? 'wholesale_saved_updated' : 'wholesale_saved_sent',
          )),
        ),
      );
      await _offerVideo(productId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content:
              Text(context.tr('error_generic').replaceAll('{error}', '$e'))),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content:
              Text(context.tr('error_generic').replaceAll('{error}', '$e'))),
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _imagesSection(),
            const SizedBox(height: 16),
            TextFormField(
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
            _tiersSection(),
            const SizedBox(height: 16),
            _shippingSection(),
            const SizedBox(height: 12),
            TextFormField(
              controller: _unitCtrl,
              // Поғона ёрлиқлари («1–9 дона» ва ҳ.к.) шу бирликка эргашади.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: context.tr('wholesale_field_unit'),
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
              label: Text(c.label),
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

  /// Етказиш учун вазн/ўлчам (У1). Пулли вазн жонли кўрсатилади — сотувчи
  /// катта қути учун ҳажмий вазн ҳақиқийдан ошишини кўради.
  Widget _shippingSection() {
    final unit = _unitCtrl.text.trim().isEmpty ? 'дона' : _unitCtrl.text.trim();
    final s = _collectShipping();
    String? preview;
    if (s.error == null && s.weightG != null) {
      final vol = s.dims?.volumetricWeightG() ?? 0;
      preview = context
          .tr('wholesale_chargeable_weight')
          .replaceAll('{weight}', formatWeightG(chargeableWeightG(s.weightG!, s.dims)))
          .replaceAll('{vol}', s.dims == null ? '—' : formatWeightG(vol));
    }
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('wholesale_shipping_section'),
            style: const TextStyle(
                fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          context.tr('wholesale_shipping_help'),
          style: TextStyle(fontSize: AppText.labelTiny, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _weightCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          onChanged: (_) => setState(() {}),
          decoration: deco(context.tr('wholesale_field_weight_kg').replaceAll('{unit}', unit)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          for (final (ctrl, key) in [
            (_dimLCtrl, 'wholesale_field_dim_l'),
            (_dimWCtrl, 'wholesale_field_dim_w'),
            (_dimHCtrl, 'wholesale_field_dim_h'),
          ]) ...[
            Expanded(
              child: TextFormField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                onChanged: (_) => setState(() {}),
                decoration: deco(context.tr(key)),
              ),
            ),
            if (key != 'wholesale_field_dim_h') const SizedBox(width: 8),
          ],
        ]),
        if (preview != null) ...[
          const SizedBox(height: 6),
          Text(preview, style: TextStyle(fontSize: AppText.labelTiny, color: AppColors.primaryText)),
        ] else if (s.error != null) ...[
          const SizedBox(height: 6),
          Text(context.tr(s.error!), style: TextStyle(fontSize: AppText.labelTiny, color: Colors.red.shade700)),
        ],
      ],
    );
  }

  Widget _tiersSection() {
    final unit = _unitCtrl.text.trim().isEmpty ? 'дона' : _unitCtrl.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('wholesale_price_tiers'),
            style: const TextStyle(
                fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          context.tr('wholesale_tiers_help'),
          style: TextStyle(fontSize: AppText.labelTiny, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _kFixedTiers.length; i++) _tierRow(i, unit),
      ],
    );
  }

  Widget _tierRow(int index, String unit) {
    final tier = _kFixedTiers[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(
          width: 96,
          child: Text(
            '${tier.rangeLabel} $unit',
            style: const TextStyle(
                fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: _priceCtrls[index],
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: context
                  .tr('wholesale_field_tier_price')
                  .replaceAll('{currency}', _currencyLabel),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _imagesSection() {
    return Column(
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
              child: Image.network(_existingImageUrls[i], fit: BoxFit.cover),
              onRemove: () => _removeExisting(i),
            ),
          for (var i = 0; i < _newImages.length; i++)
            _imageThumb(
              child: _XFileImage(_newImages[i]),
              onRemove: () => _removeNew(i),
            ),
          if (_totalImageCount < _maxImages)
            InkWell(
              onTap: _pickImages,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_a_photo_outlined),
              ),
            ),
        ]),
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
          child: SizedBox(
            width: 84,
            height: 84,
            child: child,
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: const CircleAvatar(
              radius: 11,
              backgroundColor: Colors.black54,
              child: Icon(Icons.close, size: 14, color: Colors.white),
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
        return Image.memory(snap.data!, fit: BoxFit.cover);
      },
    );
  }
}
