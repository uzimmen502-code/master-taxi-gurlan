import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/map_picker_result.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../../ads/services/ads_storage_service.dart';
import '../../map_picker/screens/map_picker_screen.dart';
import '../realty_tabs.dart';
import 'realty_pro_screen.dart';

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
  const AddRealtyListingScreen({
    super.key,
    this.existing,
    this.copyFrom,
  });

  /// Бўш бўлмаса — таҳрирлаш режими.
  final RealtyListing? existing;

  /// «Нусха олиш» (концепция, 5-бўлим): олдинги объектдан нусха —
  /// фақат қават, хона, майдон ва нарх ўзгартирилади, харитадаги нуқта
  /// шу уйда қолади. Янги ЁЗУВ яратилади, [existing] эмас.
  final RealtyListing? copyFrom;

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

  /// Банд/бепул объект ўрни. Янги объектда экран очилиши билан
  /// ўқилади — фойдаланувчи формани тўлдириб бўлиб, сақлашда «лимит
  /// тугади» эшитмасин (қурилмада сезилди, 2026-09-29).
  RealtyQuota _quota = RealtyQuota.empty;

  /// `RealtyQuota.empty` да `limit == 0`, яъни `isFull` ҳам `true` —
  /// юкланмасдан туриб «лимит тугади» деб кўрсатмаслик учун керак.
  bool _quotaLoaded = false;

  /// Расмлар БИТТА рўйхатда: аввал юкланганлари (URL) ва ҳозир
  /// танланганлари (локал файл) аралаш туради. Битта рўйхат бўлгани
  /// учун тартибни суриб ўзгартириш мумкин — биринчиси муқова бўлади
  /// (концепция, 5-бўлим: «кўп расм юклаш ва тартибини ўзгартириш»).
  final List<_PhotoItem> _photos = [];
  bool _submitting = false;

  Color get _tierColor => RealtyTabs.colorFor(_tier);

  int get _imageCount => _photos.length;

  /// Манзил МАЖБУРИЙ (эга қарори, 2026-09-29). Харитадаги нуқта
  /// тахминий кўрсаткич, матнли манзил эса харидорга — кўча, уй, мўлжал.
  /// Иккови бир-бирини алмаштирмайди, шунинг учун иккови ҳам талаб
  /// қилинади. Сервер ҳам шуни текширади (`address_required`).
  bool get _addressOk => _addressCtrl.text.trim().length >= 5;

  bool get _canSubmit =>
      !_submitting &&
      _point != null &&
      _addressOk &&
      _titleCtrl.text.trim().length >= 3 &&
      _textCtrl.text.trim().length >= 3;

  /// Қоралама калити — фақат янги, бўш форма учун (концепция, 5-бўлим:
  /// «объектни бўлиб-бўлиб тўлдириш мумкин»). Таҳрир ва нусхада
  /// қоралама ишлатилмайди: улар аллақачон тўлдирилган формадан
  /// бошланади.
  static const _draftKey = 'realty_draft_v1';

  @override
  void initState() {
    super.initState();
    // Таҳрирда ўрин сони ўзгармайди — квота фақат янги объектга керак.
    if (!_isEdit) _loadQuota();
    final source = widget.existing ?? widget.copyFrom;
    if (source == null) {
      _restoreDraft();
      _applyTemplate();
      return;
    }
    _deal = source.deal;
    _contact = source.contactMode;
    _titleCtrl.text = source.title;
    _textCtrl.text = source.text;
    _addressCtrl.text = source.addressText;
    _totalFloorsCtrl.text = source.totalFloors?.toString() ?? '';

    if (widget.existing != null) {
      // Таҳрир — ҳаммаси ўз ҳолича.
      _tier = source.tier;
      _priceCtrl.text = source.priceText;
      _roomsCtrl.text = source.rooms?.toString() ?? '';
      _floorCtrl.text = source.floor?.toString() ?? '';
      _areaCtrl.text = source.areaM2 == null ? '' : '${source.areaM2}';
      _photos.addAll(source.imageUrls.map(_PhotoItem.url));
    }
    // Нусхада қават, хона, майдон, нарх ва расмлар АТАЙЛАБ бўш
    // қолдирилади — концепцияда айнан шулар ўзгартирилади дейилган.

    _loadPoint(source.id);
  }

  Future<void> _loadQuota() async {
    try {
      final q = await _repo.fetchQuota();
      if (!mounted) return;
      setState(() {
        _quota = q;
        _quotaLoaded = true;
      });
    } catch (e) {
      // Квота ўқилмаса форма барибир ишлайди — лимитни сервер айтади.
      debugPrint('[AddRealty] loadQuota $e');
    }
  }

  /// Бепул ўрин тугаганда пакет таклифи.
  ///
  /// Аввал фақат «Бепул лимит тугади» деган SnackBar чиқар эди —
  /// фойдаланувчига НИМА ҚИЛИШ кераклиги айтилмас, риэлтор пакети
  /// экрани эса фақат профил орқали топилар эди (қурилмада сезилди,
  /// 2026-09-29).
  Future<void> _offerProPackage() async {
    final bought = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(context.tr('realty_limit_dialog_title')),
        content: Text(context.tr('realty_limit_dialog_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(context.tr('realty_limit_dialog_cta')),
          ),
        ],
      ),
    );
    if (bought != true || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RealtyProScreen()),
    );
    // Пакет олинган бўлиши мумкин — ўринни қайта ўқиймиз.
    if (mounted) await _loadQuota();
  }

  /// Қораламани тиклаш. Расмлар сақланмайди — локал файл йўллари
  /// илова қайта очилганда ишончсиз бўлади.
  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null || raw.isEmpty || !mounted) return;
      final d = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _deal = RealtyDealX.parse(d['deal']);
        _contact = RealtyContactModeX.parse(d['contact']);
        _titleCtrl.text = (d['title'] ?? '') as String;
        _textCtrl.text = (d['text'] ?? '') as String;
        _priceCtrl.text = (d['price'] ?? '') as String;
        _addressCtrl.text = (d['address'] ?? '') as String;
        _roomsCtrl.text = (d['rooms'] ?? '') as String;
        _floorCtrl.text = (d['floor'] ?? '') as String;
        _totalFloorsCtrl.text = (d['totalFloors'] ?? '') as String;
        _areaCtrl.text = (d['area'] ?? '') as String;
        final lat = (d['lat'] as num?)?.toDouble();
        final lng = (d['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          _point = MapPickerResult(
            lat: lat,
            lng: lng,
            label: (d['pointLabel'] ?? '') as String,
          );
        }
      });
    } catch (e) {
      debugPrint('[AddRealty] restoreDraft $e');
    }
  }

  Future<void> _saveDraft() async {
    if (_isEdit || widget.copyFrom != null) return;
    if (_titleCtrl.text.trim().isEmpty && _textCtrl.text.trim().isEmpty) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey, jsonEncode({
        'deal': _deal.key,
        'contact': _contact.key,
        'title': _titleCtrl.text,
        'text': _textCtrl.text,
        'price': _priceCtrl.text,
        'address': _addressCtrl.text,
        'rooms': _roomsCtrl.text,
        'floor': _floorCtrl.text,
        'totalFloors': _totalFloorsCtrl.text,
        'area': _areaCtrl.text,
        if (_point != null) 'lat': _point!.lat,
        if (_point != null) 'lng': _point!.lng,
        if (_point != null) 'pointLabel': _point!.label,
      }));
    } catch (e) {
      debugPrint('[AddRealty] saveDraft $e');
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  /// Шаблон — компаниянинг стандарт матни (концепция, 5-бўлим).
  /// Фақат янги, бўш формага тўлади; нусха ёки таҳрирга тегмайди.
  Future<void> _applyTemplate() async {
    final text = await _repo.loadTemplateText();
    if (!mounted || text.isEmpty || _textCtrl.text.trim().isNotEmpty) return;
    setState(() => _textCtrl.text = text);
  }

  /// Аниқ координата очиқ ҳужжатда йўқ (у пуллик ахборот) — эга учун
  /// ёпиқ `private/detail` дан ўқилади. Келгунча нуқта майдони «бўш»
  /// кўринади ва сақлаш тугмаси ўчиқ туради, шунда эга тасодифан
  /// координатасиз сақлаб юбормайди.
  Future<void> _loadPoint(String listingId) async {
    final detail = await _repo.fetchDetail(listingId);
    if (!mounted || detail == null) return;
    setState(() {
      _point = MapPickerResult(
        lat: detail.lat,
        lng: detail.lng,
        label: _addressCtrl.text,
      );
    });
  }

  @override
  void dispose() {
    // Экран ёпилганда ёзилгани сақланиб қолади — фойдаланувчи кейин
    // давом эттиради.
    _saveDraft();
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

  /// «Сақланган уйлар» — рўйхатдан танлаш, пин қайта қўйилмайди.
  Future<void> _pickSavedPlace() async {
    final place = await showModalBottomSheet<RealtySavedPlace>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: StreamBuilder<List<RealtySavedPlace>>(
          stream: _repo.watchSavedPlaces(),
          builder: (context, snap) {
            final places = snap.data ?? const <RealtySavedPlace>[];
            if (places.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.tr('realty_saved_places_empty'),
                  textAlign: TextAlign.center,
                ),
              );
            }
            return ListView(
              shrinkWrap: true,
              children: [
                for (final p in places)
                  ListTile(
                    leading: const Icon(Icons.home_work_outlined),
                    title: Text(p.label),
                    onTap: () => Navigator.of(sheetCtx).pop(p),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => _repo.deleteSavedPlace(p.id),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
    if (place == null || !mounted) return;
    setState(() {
      _point = MapPickerResult(
        lat: place.lat,
        lng: place.lng,
        label: place.label,
      );
      if (_addressCtrl.text.trim().isEmpty) _addressCtrl.text = place.label;
    });
  }

  /// Танланган нуқтани «сақланган уйлар»га қўшиш.
  Future<void> _saveCurrentPlace() async {
    final point = _point;
    if (point == null) return;
    final label = _addressCtrl.text.trim().isNotEmpty
        ? _addressCtrl.text.trim()
        : point.label.trim();
    if (label.isEmpty) return;
    await _repo.savePlace(label: label, lat: point.lat, lng: point.lng);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr('realty_place_saved')),
      behavior: SnackBarBehavior.floating,
    ));
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
      _photos.addAll(picked.take(room).map(_PhotoItem.file));
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
      final newFiles = _photos.where((p) => p.file != null).toList();
      if (newFiles.isNotEmpty) {
        final ownerId = canonicalPhoneId(
          FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
        );
        uploaded = await _storage.uploadImages(
          ownerId: ownerId,
          images: newFiles.map((p) => p.file!).toList(),
        );
      }
      // Экрандаги ТАРТИБ сақланади: янги юкланган URL'лар ўз ўрнига
      // қўйилади, шунда фойдаланувчи сурган тартиб базага ҳам тушади.
      var nextUpload = 0;
      final images = [
        for (final p in _photos)
          if (p.url != null) p.url! else uploaded[nextUpload++],
      ];
      final keptUrls = _photos
          .where((p) => p.url != null)
          .map((p) => p.url!)
          .toList();
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
          : existing.imageUrls.where((u) => !keptUrls.contains(u)).toList();
      if (removed.isNotEmpty) {
        await _storage.deleteAdImages(
          ownerId: canonicalPhoneId(
            FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
          ),
          imageUrls: removed,
        );
      }
      if (!mounted) return;
      // Матн қораламани тозалашдан ОЛДИН олинади: `await` дан кейин
      // `context` ишлатиш хавфли (экран ёпилган бўлиши мумкин).
      final message = context.tr(
        _isEdit
            ? (result.isLive ? 'realty_saved' : 'realty_submit_pending')
            : (result.isLive ? 'realty_submit_live' : 'realty_submit_pending'),
      );
      await _clearDraft();
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(message),
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
      // Лимит тугаган бўлса — хабар эмас, ЧИҚИШ ЙЎЛИ кўрсатилади.
      if (e.code == 'free_limit_reached') {
        await _loadQuota();
        if (mounted) await _offerProPackage();
        return;
      }
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
      case 'address_required':
        return context.tr('realty_error_address');
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
            // «Сақланган уйлар» — риэлтор бир хил уйга пин қўявермасин.
            Row(
              children: [
                TextButton.icon(
                  onPressed: _submitting ? null : _pickSavedPlace,
                  icon: const Icon(Icons.home_work_outlined, size: 16),
                  label: Text(context.tr('realty_saved_places')),
                ),
                const Spacer(),
                if (_point != null)
                  TextButton.icon(
                    onPressed: _submitting ? null : _saveCurrentPlace,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                    label: Text(context.tr('realty_save_place')),
                  ),
              ],
            ),
            const SizedBox(height: 8),

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
            _field(
              _addressCtrl,
              'realty_field_address',
              maxLength: 300,
              required: true,
              // Янги, ҳали тегилмаган формада қизил хато чиқмасин;
              // таҳрирда эса эски (манзилсиз) эълон дарҳол кўрсатилади.
              showError: !_addressOk && (_isEdit || _addressCtrl.text.isNotEmpty),
              helper: context.tr('realty_field_address_hint'),
            ),
            const SizedBox(height: 16),

            _label(context, 'realty_field_photos'),
            _PhotoStrip(
              photos: _photos,
              onAdd: (_submitting || _imageCount >= _maxImages)
                  ? null
                  : _pickImages,
              onRemove: (i) => setState(() => _photos.removeAt(i)),
              onReorder: (from, to) => setState(() {
                final item = _photos.removeAt(from);
                _photos.insert(to > from ? to - 1 : to, item);
              }),
              addLabel: context.tr('realty_add_photo'),
            ),
            if (_photos.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.tr('realty_photo_order_hint'),
                  style: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
                ),
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
            if (!_isEdit) _quotaStrip(context),
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
    bool required = false,
    bool showError = false,
    String? helper,
  }) {
    final c = context.ava;
    final errColor = RealtyTabs.colorFor(RealtyTier.urgent);
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
        // Мажбурий майдон — юлдузча билан, харитадаги нуқта майдони
        // билан бир хил андоза.
        labelText:
            required ? '${context.tr(labelKey)} *' : context.tr(labelKey),
        labelStyle: TextStyle(color: c.ink2, fontWeight: FontWeight.w600),
        helperText: helper,
        helperMaxLines: 2,
        helperStyle: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
        errorText: showError ? context.tr('realty_error_address') : null,
        filled: true,
        fillColor: c.surface,
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: showError ? errColor : c.line,
            width: showError ? 1.5 : 1,
          ),
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

  /// Банд ўрин йўлакчаси — статик «2 тагача бепул» ёзуви ўрнига.
  ///
  /// Ўрин тугаган бўлса шу ернинг ўзида «Пакет олиш» тугмаси чиқади:
  /// фойдаланувчи формани тўлдиришдан ОЛДИН билиб олсин.
  Widget _quotaStrip(BuildContext context) {
    final c = context.ava;
    if (!_quotaLoaded) {
      return Center(
        child: Text(
          context.tr('realty_free_limit_hint'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
        ),
      );
    }
    final full = _quota.isFull;
    final accent = full ? RealtyTabs.colorFor(RealtyTier.urgent) : c.ink3;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _quota.isPro
                  ? Icons.workspace_premium_outlined
                  : Icons.home_outlined,
              size: 15,
              color: accent,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${context.tr(_quota.isPro ? 'realty_pro_quota' : 'realty_my_free_slots')}'
                ': ${_quota.used} / ${_quota.limit}',
                style: TextStyle(
                  fontSize: AppText.labelTiny,
                  color: accent,
                  fontWeight: full ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (full) ...[
          const SizedBox(height: 6),
          Text(
            context.tr('realty_limit_dialog_body'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _offerProPackage,
            icon: const Icon(Icons.workspace_premium_outlined, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.brand,
              side: BorderSide(color: c.brand),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            label: Text(context.tr('realty_limit_dialog_cta')),
          ),
        ],
      ],
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

/// Тасмадаги битта расм — ё аввал юкланган URL, ё ҳозир танланган файл.
class _PhotoItem {
  const _PhotoItem._(this.url, this.file);

  factory _PhotoItem.url(String url) => _PhotoItem._(url, null);
  factory _PhotoItem.file(XFile file) => _PhotoItem._(null, file);

  final String? url;
  final XFile? file;
}

/// Расмлар тасмаси — босиб туриб суриш билан тартиб ўзгаради.
/// Биринчиси муқова бўлади, шунинг учун унда «муқова» белгиси бор.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
    required this.addLabel,
  });

  final List<_PhotoItem> photos;
  final VoidCallback? onAdd;
  final void Function(int index) onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return SizedBox(
      height: 96,
      child: Row(
        children: [
          GestureDetector(
            onTap: onAdd,
            child: Opacity(
              opacity: onAdd == null ? 0.45 : 1,
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
          ),
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: photos.length,
              onReorder: onReorder,
              itemBuilder: (context, i) => ReorderableDragStartListener(
                key: ValueKey(photos[i].url ?? photos[i].file!.path),
                index: i,
                child: Stack(
                  children: [
                    Container(
                      width: 96,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: i == 0 ? c.brand : c.line,
                          width: i == 0 ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _thumb(context, photos[i]),
                    ),
                    Positioned(
                      right: 12,
                      top: 4,
                      child: GestureDetector(
                        onTap: () => onRemove(i),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (i == 0)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.brand,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            context.tr('realty_photo_cover'),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: c.brandInk,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumb(BuildContext context, _PhotoItem item) {
    final c = context.ava;
    final url = item.url;
    if (url != null) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: c.surface2,
          child: Icon(Icons.image, color: c.ink3),
        ),
      );
    }
    // Web'да `XFile.path` — blob URL, мобилда реал файл йўли.
    return kIsWeb
        ? Image.network(item.file!.path, fit: BoxFit.cover)
        : Image.file(File(item.file!.path), fit: BoxFit.cover);
  }
}

