import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/map_picker_result.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../../ads/services/ads_storage_service.dart';
import '../../map_picker/screens/map_picker_screen.dart';
import '../realty_tabs.dart';

/// Кўчмас мулк объекти — янгисини қўшиш ва мавжудини таҳрирлаш.
///
/// Иккови битта экран: майдонлар, текширувлар ва харитага боғлаш қоидаси
/// айнан бир хил, фақат сақлаш йўли фарқ қилади. Алоҳида «таҳрирлаш»
/// экрани қилинса, иккита жойда бир хил валидация сақлаш керак бўларди.
///
/// Асосий қоида (концепция, 7-бўлим): объект харитага боғланмаса, эълон
/// умуман жойлаштирилмайди. Шунинг учун нуқта танланмагунча сақлаш
/// тугмаси ўчиқ туради — бу фуқарога ҳам, риэлторга ҳам бирдек.
class AddRealtyListingScreen extends StatefulWidget {
  const AddRealtyListingScreen({super.key, this.existing});

  /// Бўш бўлмаса — таҳрирлаш режими.
  final RealtyListing? existing;

  @override
  State<AddRealtyListingScreen> createState() =>
      _AddRealtyListingScreenState();
}

class _AddRealtyListingScreenState extends State<AddRealtyListingScreen> {
  static const int _maxImages = 5;

  bool get _isEdit => widget.existing != null;

  final _repo = RealtyRepository();
  final _storage = AdsStorageService();

  final _titleCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _roomsCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  final _totalFloorsCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  RealtyDeal _deal = RealtyDeal.sale;
  RealtyTier _tier = RealtyTier.plain;
  RealtyContactMode _contact = RealtyContactMode.owner;

  MapPickerResult? _point;

  /// Таҳрирлашда аввал юкланган расмлар (URL) ва янги танланганлар
  /// (локал файл) ёнма-ён туради — жами [_maxImages] тадан ошмайди.
  final List<String> _keptUrls = [];
  final List<XFile> _images = [];
  bool _submitting = false;

  Color get _tierColor => RealtyTabs.colorFor(_tier);

  int get _imageCount => _keptUrls.length + _images.length;

  bool get _canSubmit =>
      !_submitting &&
      _point != null &&
      _titleCtrl.text.trim().length >= 3 &&
      _textCtrl.text.trim().length >= 3;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e == null) return;
    _deal = e.deal;
    _tier = e.tier;
    _contact = e.contactMode;
    _titleCtrl.text = e.title;
    _textCtrl.text = e.text;
    _priceCtrl.text = e.priceText;
    _addressCtrl.text = e.addressText;
    _roomsCtrl.text = e.rooms?.toString() ?? '';
    _floorCtrl.text = e.floor?.toString() ?? '';
    _totalFloorsCtrl.text = e.totalFloors?.toString() ?? '';
    _areaCtrl.text = e.areaM2 == null ? '' : '${e.areaM2}';
    _keptUrls.addAll(e.imageUrls);
    _point = MapPickerResult(
      lat: e.lat,
      lng: e.lng,
      label: e.addressText,
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _textCtrl.dispose();
    _priceCtrl.dispose();
    _roomsCtrl.dispose();
    _floorCtrl.dispose();
    _totalFloorsCtrl.dispose();
    _areaCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPoint() async {
    final result = await Navigator.of(context).push<MapPickerResult>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(title: context.tr('realty_pick_point')),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _point = result;
      if (_addressCtrl.text.trim().isEmpty && result.label.trim().isNotEmpty) {
        _addressCtrl.text = result.label.trim();
      }
    });
  }

  Future<void> _pickImages() async {
    final room = _maxImages - _imageCount;
    if (room <= 0) return;
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 85,
      limit: room,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _images.addAll(picked.take(room));
    });
  }

  Future<void> _submit() async {
    final point = _point;
    if (point == null) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    var uploaded = const <String>[];
    try {
      if (_images.isNotEmpty) {
        final ownerId = canonicalPhoneId(
          FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
        );
        uploaded = await _storage.uploadImages(
          ownerId: ownerId,
          images: _images,
        );
      }
      // Таҳрирлашда: сақлаб қолинганлар + янги юкланганлар.
      final images = [..._keptUrls, ...uploaded];
      final existing = widget.existing;
      final result = existing == null
          ? await _repo.submitListing(
              deal: _deal,
              tier: _tier,
              title: _titleCtrl.text,
              text: _textCtrl.text,
              lat: point.lat,
              lng: point.lng,
              contactMode: _contact,
              priceText: _priceCtrl.text,
              addressText: _addressCtrl.text,
              rooms: int.tryParse(_roomsCtrl.text.trim()),
              floor: int.tryParse(_floorCtrl.text.trim()),
              totalFloors: int.tryParse(_totalFloorsCtrl.text.trim()),
              areaM2: num.tryParse(_areaCtrl.text.trim().replaceAll(',', '.')),
              imageUrls: images,
            )
          : await _repo.updateListing(
              listingId: existing.id,
              deal: _deal,
              title: _titleCtrl.text,
              text: _textCtrl.text,
              lat: point.lat,
              lng: point.lng,
              contactMode: _contact,
              priceText: _priceCtrl.text,
              addressText: _addressCtrl.text,
              rooms: int.tryParse(_roomsCtrl.text.trim()),
              floor: int.tryParse(_floorCtrl.text.trim()),
              totalFloors: int.tryParse(_totalFloorsCtrl.text.trim()),
              areaM2: num.tryParse(_areaCtrl.text.trim().replaceAll(',', '.')),
              imageUrls: images,
            );
      // Эга олиб ташлаган эски расмлар Storage'да қолиб кетмасин.
      final removed = existing == null
          ? const <String>[]
          : existing.imageUrls.where((u) => !_keptUrls.contains(u)).toList();
      if (removed.isNotEmpty) {
        await _storage.deleteAdImages(
          ownerId: canonicalPhoneId(
            FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
          ),
          imageUrls: removed,
        );
      }
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr(
          _isEdit
              ? (result.isLive ? 'realty_saved' : 'realty_submit_pending')
              : (result.isLive ? 'realty_submit_live' : 'realty_submit_pending'),
        )),
        backgroundColor: _tierColor,
        behavior: SnackBarBehavior.floating,
      ));
    } on RealtyException catch (e) {
      // Эълон яратилмади — юкланган расмлар Storage'да эгасиз қолмасин.
      if (uploaded.isNotEmpty) {
        await _storage.deleteAdImages(
          ownerId: canonicalPhoneId(
            FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
          ),
          imageUrls: uploaded,
        );
      }
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(
        content: Text(_errorText(e)),
        backgroundColor: RealtyTabs.colorFor(RealtyTier.urgent),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr('realty_error_generic')),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  String _errorText(RealtyException e) {
    switch (e.code) {
      case 'free_limit_reached':
        return context.tr('realty_error_free_limit');
      case 'location_required':
        return context.tr('realty_error_location');
      case 'tier_not_available':
        return context.tr('realty_error_tier_soon');
      default:
        return context.tr('realty_error_generic');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(
          context.tr(_isEdit ? 'realty_edit_title' : 'realty_add_title'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _label(context, 'realty_field_deal'),
            Row(
              children: [
                _choice(
                  context.tr('realty_deal_sale'),
                  _deal == RealtyDeal.sale,
                  () => setState(() => _deal = RealtyDeal.sale),
                ),
                const SizedBox(width: 8),
                _choice(
                  context.tr('realty_deal_rent'),
                  _deal == RealtyDeal.rent,
                  () => setState(() => _deal = RealtyDeal.rent),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _label(context, 'realty_field_tier'),
            Row(
              children: [
                for (final tier in RealtyTabs.order) ...[
                  _choice(
                    context.tr(RealtyTabs.labelKey(tier)),
                    _tier == tier,
                    // Таҳрирлашда даража ўзгармайди: РЕКЛАМА/СРОЧНО
                    // тўлов иши, уни таҳрир орқали олиб бўлмайди.
                    (_isEdit || !tier.isPurchasable)
                        ? null
                        : () => setState(() => _tier = tier),
                    color: RealtyTabs.colorFor(tier),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                _isEdit ? 'realty_tier_locked_hint' : 'realty_tier_paid_soon_hint',
              ),
              style: TextStyle(fontSize: AppText.labelSmall, color: c.ink3),
            ),
            const SizedBox(height: 16),

            // ─── Харитага боғлаш — мажбурий ───
            _PointField(
              point: _point,
              onTap: _pickPoint,
              color: _tierColor,
            ),
            const SizedBox(height: 16),

            _field(_titleCtrl, 'realty_field_title', maxLength: 120),
            const SizedBox(height: 10),
            _field(_textCtrl, 'realty_field_text',
                maxLines: 5, maxLength: 2000),
            const SizedBox(height: 10),
            _field(_priceCtrl, 'realty_field_price', maxLength: 80),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _field(_roomsCtrl, 'realty_field_rooms',
                      numeric: true, maxLength: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(_floorCtrl, 'realty_field_floor',
                      numeric: true, maxLength: 3),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(_totalFloorsCtrl, 'realty_field_total_floors',
                      numeric: true, maxLength: 3),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _field(_areaCtrl, 'realty_field_area', numeric: true, maxLength: 7),
            const SizedBox(height: 10),
            _field(_addressCtrl, 'realty_field_address', maxLength: 300),
            const SizedBox(height: 16),

            _label(context, 'realty_field_photos'),
            _PhotoStrip(
              keptUrls: _keptUrls,
              images: _images,
              onAdd: (_submitting || _imageCount >= _maxImages)
                  ? null
                  : _pickImages,
              onRemoveUrl: (i) => setState(() => _keptUrls.removeAt(i)),
              onRemove: (i) => setState(() => _images.removeAt(i)),
              addLabel: context.tr('realty_add_photo'),
            ),
            const SizedBox(height: 16),

            _label(context, 'realty_field_contact'),
            Row(
              children: [
                _choice(
                  context.tr('realty_contact_owner'),
                  _contact == RealtyContactMode.owner,
                  () => setState(() => _contact = RealtyContactMode.owner),
                ),
                const SizedBox(width: 8),
                _choice(
                  context.tr('realty_contact_agent'),
                  _contact == RealtyContactMode.avaAgent,
                  () => setState(() => _contact = RealtyContactMode.avaAgent),
                ),
              ],
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _tierColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      context.tr(_isEdit ? 'save' : 'realty_add_cta'),
                      style: const TextStyle(
                        fontSize: AppText.bodyLarge,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            // Бепул лимит фақат янги объектга тегишли — таҳрирлашда
            // ўрин сони ўзгармайди.
            if (!_isEdit)
              Center(
                child: Text(
                  context.tr('realty_free_limit_hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String key) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        context.tr(key),
        style: TextStyle(
          fontSize: AppText.labelLarge,
          fontWeight: FontWeight.w700,
          color: c.ink2,
        ),
      ),
    );
  }

  Widget _choice(String label, bool selected, VoidCallback? onTap,
      {Color? color}) {
    final c = context.ava;
    final active = color ?? c.brand;
    return Expanded(
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: selected ? active : c.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? active : c.line),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppText.bodySmall,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : c.ink2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String labelKey, {
    int maxLines = 1,
    int? maxLength,
    bool numeric = false,
  }) {
    final c = context.ava;
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters:
          numeric ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))] : null,
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: c.ink),
      decoration: InputDecoration(
        labelText: context.tr(labelKey),
        labelStyle: TextStyle(color: c.ink2, fontWeight: FontWeight.w600),
        filled: true,
        fillColor: c.surface,
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _tierColor, width: 1.5),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

/// Харитадаги нуқта майдони — танланмагунча қизил контур билан туради.
class _PointField extends StatelessWidget {
  const _PointField({
    required this.point,
    required this.onTap,
    required this.color,
  });

  final MapPickerResult? point;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final chosen = point != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: chosen ? color : RealtyTabs.colorFor(RealtyTier.urgent),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              chosen ? Icons.place : Icons.add_location_alt_outlined,
              color: chosen ? color : RealtyTabs.colorFor(RealtyTier.urgent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(
                      chosen ? 'realty_point_chosen' : 'realty_point_required',
                    ),
                    style: TextStyle(
                      fontSize: AppText.bodyMedium,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  if (chosen)
                    Text(
                      point!.label.isNotEmpty
                          ? point!.label
                          : '${point!.lat.toStringAsFixed(5)}, '
                              '${point!.lng.toStringAsFixed(5)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.labelSmall,
                        color: c.ink3,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.ink3),
          ],
        ),
      ),
    );
  }
}

/// Расмлар тасмаси: таҳрирлашда аввал сақланган расмлар (URL) олдинда,
/// ҳозир танланган янгилари кейин туради. Иккови ҳам ўчирилиши мумкин.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.keptUrls,
    required this.images,
    required this.onAdd,
    required this.onRemoveUrl,
    required this.onRemove,
    required this.addLabel,
  });

  final List<String> keptUrls;
  final List<XFile> images;
  final VoidCallback? onAdd;
  final void Function(int index) onRemoveUrl;
  final void Function(int index) onRemove;
  final String addLabel;

  Widget _removeBadge(VoidCallback onTap) {
    return Positioned(
      right: 12,
      top: 4,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 14, color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 96,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.line),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, color: c.ink3),
                  const SizedBox(height: 4),
                  Text(
                    addLabel,
                    style: TextStyle(
                      fontSize: AppText.labelTiny,
                      color: c.ink3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (var i = 0; i < keptUrls.length; i++)
            Stack(
              children: [
                Container(
                  width: 96,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.network(
                    keptUrls[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: c.surface2,
                      child: Icon(Icons.image, color: c.ink3),
                    ),
                  ),
                ),
                _removeBadge(() => onRemoveUrl(i)),
              ],
            ),
          for (var i = 0; i < images.length; i++)
            Stack(
              children: [
                Container(
                  width: 96,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  // Web'да `XFile.path` — blob URL, мобилда эса реал
                  // файл йўли (`create_ad_screen.dart`даги каби).
                  child: kIsWeb
                      ? Image.network(images[i].path, fit: BoxFit.cover)
                      : Image.file(File(images[i].path), fit: BoxFit.cover),
                ),
                _removeBadge(() => onRemove(i)),
              ],
            ),
        ],
      ),
    );
  }
}
