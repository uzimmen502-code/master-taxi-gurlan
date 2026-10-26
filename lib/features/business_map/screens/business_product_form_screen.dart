import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../tv_market/screens/tv_publish_screen.dart';
import '../../tv_market/screens/tv_shop_item_photos_screen.dart';
import '../../tv_market/services/tv_storage_service.dart';
import '../domain/business.dart';
import '../domain/product_kind.dart';

/// Объектнинг маҳсулот/хизмати: ном, нарх, тавсиф, 7 тагача расм, ихтиёрий 1 видео (эга қарори, 2026-10-24).
///
/// Маҳсулот — мавжуд АВАГрам витринаси ҳужжати (`tv_shop_items`) + `businessId`: Аҳоли бозорида (расм бор) ва
/// видео қўшилса АВАГрамда ўзи чиқади. Модерациясиз: эга ўзи жойлайди, админ таҳрирлайди/ўчиради.
class BusinessProductFormScreen extends StatefulWidget {
  const BusinessProductFormScreen({
    super.key,
    required this.business,
    this.existing,
    TvShopRepository? repository,
    this.ownerPhone,
    this.pickPhotos,
    this.uploadPhotos,
    this.addVideo,
  }) : _repo = repository;

  final Business business;
  final TvShopItem? existing;
  final TvShopRepository? _repo;

  /// Тест учун; бўлмаса — жорий фойдаланувчи телефони.
  final String? ownerPhone;

  /// Тест учун алмаштирилади (платформа плагинлари). `room` — яна неча расм сиғади.
  final Future<List<String>> Function(int room)? pickPhotos;
  final Future<List<String>> Function(String ownerPhone, List<String> paths)? uploadPhotos;

  /// Расм сақлангандан кейин видео қўшиш (бўлмаса — АВАГрам нашр экрани очилади).
  final Future<void> Function(BuildContext context, String itemId)? addVideo;

  @override
  State<BusinessProductFormScreen> createState() => _BusinessProductFormScreenState();
}

class _BusinessProductFormScreenState extends State<BusinessProductFormScreen> {
  late final TvShopRepository _repo = widget._repo ?? TvShopRepository();
  late final String _phone =
      widget.ownerPhone ?? canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');

  late final TextEditingController _name = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _price = TextEditingController(
      text: (widget.existing?.price ?? 0) > 0 ? '${widget.existing!.price}' : '');
  late final TextEditingController _desc = TextEditingController(text: widget.existing?.description ?? '');
  late String _kind = widget.existing?.kind ??
      (sellsOnlyProducts(widget.business) ? 'product' : defaultProductKind(widget.business.category));

  /// Дўконда «Хизмат» танлови йўқ ([sellsOnlyProducts]). Аввал хизмат деб сақланган эски дўкон ёзуви — танлов
  /// кўринади, эга уни маҳсулотга ўтказа олсин.
  late final bool _showKindChoice = !sellsOnlyProducts(widget.business) || widget.existing?.kind == 'service';
  final List<String> _photos = [];
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<List<String>> _defaultPick(int room) async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 88, limit: room >= 2 ? room : null);
    return [for (final f in picked) f.path];
  }

  Future<void> _pick() async {
    final room = TvShopItem.maxPhotos - _photos.length;
    if (room <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('tv_shop_photos_max'))));
      return;
    }
    final paths = await (widget.pickPhotos ?? _defaultPick)(room);
    if (paths.isEmpty || !mounted) return;
    setState(() => _photos.addAll(paths.take(room)));
  }

  Future<List<String>> _defaultUpload(String phone, List<String> paths) =>
      TvStorageService().uploadShopPhotos(ownerPhone: phone, filePaths: paths);

  Future<void> _defaultAddVideo(BuildContext context, String itemId) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TvPublishScreen(attachItemId: itemId)));

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) return setState(() => _error = context.tr('bizprod_err_name'));
    final price = parseProductPrice(_price.text);
    if (price == null) return setState(() => _error = context.tr('bizprod_err_price'));
    if (!_isEdit && _photos.isEmpty) return setState(() => _error = context.tr('tv_shop_photo_required'));
    if (_phone.isEmpty) return setState(() => _error = context.tr('bizprod_err_generic'));

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String itemId;
      if (_isEdit) {
        itemId = widget.existing!.id;
        await _repo.updateItem(itemId, {
          'title': name,
          'price': price,
          'description': _desc.text.trim(),
          'kind': _kind,
        });
      } else {
        final urls = await (widget.uploadPhotos ?? _defaultUpload)(_phone, List.of(_photos));
        if (urls.isEmpty) throw StateError('no photos uploaded');
        await _repo.ensureShop(ownerPhone: _phone, name: widget.business.name);
        itemId = await _repo.createItem(TvShopItem(
          id: '',
          ownerPhone: _phone,
          ownerName: widget.business.name,
          title: name,
          price: price,
          photoUrl: urls.first,
          photoUrls: urls,
          kind: _kind,
          districtId: widget.business.districtId,
          // Ўз дўкони (харитасиз): туман номи ҳам ёзилади — лентада кўринади; харита объектида аввалгидек бўш.
          districtLabel: widget.business.isOwnShop ? ServiceConfigHolder.districtLabel.trim() : '',
          description: _desc.text.trim(),
          status: 'active',
          businessId: widget.business.id,
        ));
      }
      if (!mounted) return;
      // Ҳужжат ёзилди: спиннер тўхтайди (видео сўрови очиқ турганда ҳам «банд» кўринмасин).
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('bizprod_saved'))));
      if (!_isEdit) await _offerVideo(itemId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('[BusinessProductForm] save: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.tr('bizprod_err_generic');
      });
    }
  }

  Future<void> _offerVideo(String itemId) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('bizprod_video_ask_title')),
        content: Text(context.tr('bizprod_video_ask_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('bizprod_video_later'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('bizprod_video_add'))),
        ],
      ),
    );
    if (yes == true && mounted) await (widget.addVideo ?? _defaultAddVideo)(context, itemId);
  }

  Widget _thumb(String path) {
    Widget broken(BuildContext _, Object __, StackTrace? ___) => const ColoredBox(color: Color(0x11000000), child: Icon(Icons.broken_image_outlined));
    final img = kIsWeb
        ? Image.network(path, fit: BoxFit.cover, errorBuilder: broken)
        : Image.file(File(path), fit: BoxFit.cover, errorBuilder: broken);
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: img);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(_isEdit ? 'bizprod_edit' : (_showKindChoice ? 'bizprod_new' : 'bizprod_new_product'))),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_showKindChoice) ...[
            SegmentedButton<String>(
              key: const ValueKey('bizprod_kind'),
              segments: [
                ButtonSegment(value: 'product', label: Text(context.tr('bizprod_kind_product'))),
                ButtonSegment(value: 'service', label: Text(context.tr('bizprod_kind_service'))),
              ],
              selected: {_kind},
              onSelectionChanged: _busy ? null : (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const ValueKey('bizprod_name'),
            controller: _name,
            enabled: !_busy,
            maxLength: 120,
            decoration: InputDecoration(labelText: context.tr('bizprod_f_name'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('bizprod_price'),
            controller: _price,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
            decoration: InputDecoration(labelText: context.tr('bizprod_f_price'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('bizprod_desc'),
            controller: _desc,
            enabled: !_busy,
            maxLines: 4,
            maxLength: 1000,
            decoration: InputDecoration(labelText: context.tr('bizprod_f_desc'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          if (_isEdit) ...[
            OutlinedButton.icon(
              key: const ValueKey('bizprod_edit_photos'),
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => TvShopItemPhotosScreen(item: widget.existing!)),
                      ),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(context.tr('bizprod_edit_photos')),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            if (!widget.existing!.hasVideo) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('bizprod_add_video'),
                onPressed: _busy
                    ? null
                    : () => (widget.addVideo ?? _defaultAddVideo)(context, widget.existing!.id),
                icon: const Icon(Icons.videocam_outlined),
                label: Text(context.tr('bizprod_video_add')),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ] else ...[
            Text('${context.tr('bizprod_photos')} ${_photos.length}/${TvShopItem.maxPhotos}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _thumb(_photos[i]),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: InkWell(
                            key: ValueKey('bizprod_photo_remove_$i'),
                            onTap: _busy ? null : () => setState(() => _photos.removeAt(i)),
                            child: const CircleAvatar(
                              radius: 11,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_photos.length < TvShopItem.maxPhotos)
                  InkWell(
                    key: const ValueKey('bizprod_add_photos'),
                    onTap: _busy ? null : _pick,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_a_photo_outlined),
                          const SizedBox(height: 4),
                          Text(context.tr('bizprod_add_photos'),
                              textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ),
          FilledButton(
            key: const ValueKey('bizprod_save'),
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size.fromHeight(50),
            ),
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr('bizmap_save')),
          ),
        ],
      ),
    );
  }
}
