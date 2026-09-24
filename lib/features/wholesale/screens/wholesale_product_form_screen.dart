import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

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
  _FixedTier(10, '10–50'),
  _FixedTier(50, '50+'),
];

/// Маҳсулот қўшиш/таҳрирлаш — ном, тавсиф, нарх поғоналари, бирлик, расм(1-5).
class WholesaleProductFormScreen extends StatefulWidget {
  const WholesaleProductFormScreen({
    super.key,
    required this.seller,
    this.existing,
  });

  final WholesaleSeller seller;

  /// `null` — янги маҳсулот, акс ҳолда — таҳрирлаш.
  final WholesaleProduct? existing;

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

  /// Ҳар бир тайёр поғона учун нарх контроллери (тартиби [_kFixedTiers]га мос).
  late final List<TextEditingController> _priceCtrls;

  final List<String> _existingImageUrls = [];
  final List<XFile> _newImages = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _unitCtrl = TextEditingController(text: e?.unit ?? 'дона');
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
    for (final c in _priceCtrls) {
      c.dispose();
    }
    super.dispose();
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
        const SnackBar(
          content: Text('Камида битта поғона нархини киритинг'),
        ),
      );
      return;
    }
    if (_totalImageCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Камида битта расм қўшинг')),
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
      );
      String productId;
      if (_isEdit) {
        productId = widget.existing!.id;
        await _repo.ownerUpdate(productId, product);
      } else {
        productId = await _repo.create(product);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit
              ? 'Маҳсулот янгиланди — қайта модерацияга юборилди'
              : 'Маҳсулот юборилди — admin тасдиғини кутинг'),
        ),
      );
      await _offerVideo(productId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
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
        title: const Text('🎥 Видеообзор қўшасизми?'),
        content: const Text(
          'Маҳсулот видеосини AVAGram лентасига жойлашингиз мумкин — '
          'бепул («Маҳсулот») ёки пуллик реклама сифатида («Реклама», '
          'тариф/муддат танлаб). Кейинроқ ҳам маҳсулот менюсидан қўша оласиз.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Кейинроқ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Видео қўшиш'),
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
        const SnackBar(content: Text('Видео маҳсулотга боғланди')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Маҳсулотни таҳрирлаш' : 'Янги маҳсулот'),
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
              decoration: const InputDecoration(
                labelText: 'Маҳсулот номи',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Камида 3 та белги'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              maxLength: 2000,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Тавсиф',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Камида 3 та белги'
                  : null,
            ),
            const SizedBox(height: 16),
            _tiersSection(),
            const SizedBox(height: 12),
            TextFormField(
              controller: _unitCtrl,
              // Поғона ёрлиқлари («1–9 дона» ва ҳ.к.) шу бирликка эргашади.
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Бирлик (дона, қути, палет...)',
                border: OutlineInputBorder(),
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
                  : Text(_isEdit ? 'Сақлаш' : 'Юбориш'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tiersSection() {
    final unit = _unitCtrl.text.trim().isEmpty ? 'дона' : _unitCtrl.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Нарх поғоналари',
            style: const TextStyle(
                fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'Сон оралиғига қараб нарх. Тўлдириш ихтиёрий — камида биттасини '
          'киритинг (бўш поғоналар сақланмайди).',
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
            decoration: const InputDecoration(
              labelText: 'Нарх (сўм) — ихтиёрий',
              border: OutlineInputBorder(),
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
        Text('Расмлар (1-$_maxImages)',
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
