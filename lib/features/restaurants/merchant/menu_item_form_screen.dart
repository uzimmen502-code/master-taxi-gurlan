// Таом қўшиш/таҳрирлаш: ном, нарх (бутун сўм), тавсиф, қадоқлаш, категория,
// расм (`restaurant_images/{rid}/`), «Бор/Йўқ».

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../data/restaurants_repository.dart';
import '../domain/restaurant_models.dart';
import '../services/restaurant_storage_service.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;

class MenuItemFormScreen extends StatefulWidget {
  const MenuItemFormScreen({
    super.key,
    required this.restaurantId,
    required this.categories,
    required this.repository,
    this.existing,
    this.initialCategoryId,
    this.storage,
  });

  final String restaurantId;
  final List<MenuCategory> categories;
  final RestaurantsRepository repository;
  final MenuItem? existing;
  final String? initialCategoryId;
  final RestaurantStorageService? storage;

  @override
  State<MenuItemFormScreen> createState() => _MenuItemFormScreenState();
}

class _MenuItemFormScreenState extends State<MenuItemFormScreen> {
  late final RestaurantStorageService _storage = widget.storage ?? RestaurantStorageService();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _price = TextEditingController(text: widget.existing == null ? '' : '${widget.existing!.price}');
  late final _desc = TextEditingController(text: widget.existing?.description ?? '');
  late final _pack = TextEditingController(text: (widget.existing?.packagingFee ?? 0) == 0 ? '' : '${widget.existing!.packagingFee}');
  late String _categoryId = widget.existing?.categoryId ?? widget.initialCategoryId ?? (widget.categories.isEmpty ? '' : widget.categories.first.id);
  late bool _available = widget.existing?.available ?? true;
  XFile? _picked;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _price, _desc, _pack]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.photo_library), title: Text(ctx.tr('gallery')), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
            ListTile(leading: const Icon(Icons.camera_alt), title: Text(ctx.tr('camera')), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ],
        ),
      ),
    );
    if (src == null) return;
    final f = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 85);
    if (f != null && mounted) setState(() => _picked = f);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = int.tryParse(_price.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    if (name.isEmpty || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('restaurants_m_err_item')), backgroundColor: Colors.red.shade700),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      var photoUrl = widget.existing?.photoUrl ?? '';
      if (_picked != null) {
        photoUrl = await _storage.uploadImage(restaurantId: widget.restaurantId, image: _picked!, kind: 'item');
      }
      await widget.repository.upsertMenuItem(
        widget.restaurantId,
        id: widget.existing?.id,
        name: name,
        price: price,
        description: _desc.text.trim(),
        photoUrl: photoUrl,
        packagingFee: int.tryParse(_pack.text.replaceAll(RegExp(r'\D'), '')) ?? 0,
        categoryId: _categoryId,
        sort: widget.existing?.sort ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        available: _available,
        stopUntil: _available ? widget.existing?.stopUntil : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(restaurantsErrorText(context, e)), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final existingPhoto = widget.existing?.photoUrl.trim() ?? '';
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(context.tr(widget.existing == null ? 'restaurants_m_add_item' : 'restaurants_m_rename'),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Center(
              child: InkWell(
                onTap: _pickPhoto,
                borderRadius: BorderRadius.circular(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 140,
                    height: 140,
                    child: _picked != null
                        ? FutureBuilder(
                            future: _picked!.readAsBytes(),
                            builder: (context, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.cover) : const SizedBox(),
                          )
                        : existingPhoto.startsWith('http')
                            ? CachedNetworkImage(imageUrl: existingPhoto, fit: BoxFit.cover)
                            : ColoredBox(
                                color: c.surface2,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo_outlined, color: c.ink3),
                                    const SizedBox(height: 4),
                                    Text(context.tr('restaurants_m_item_photo'), style: TextStyle(fontSize: 11, color: c.ink3)),
                                  ],
                                ),
                              ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(controller: _name, maxLength: 80, decoration: InputDecoration(labelText: context.tr('restaurants_m_item_name'), border: const OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 8),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: context.tr('restaurants_m_item_price'), suffixText: context.tr('sum'), border: const OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(controller: _desc, maxLength: 500, maxLines: 2, decoration: InputDecoration(labelText: context.tr('restaurants_m_item_desc'), border: const OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 8),
            TextField(
              controller: _pack,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: context.tr('restaurants_m_item_packaging'), suffixText: context.tr('sum'), border: const OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: widget.categories.any((x) => x.id == _categoryId) ? _categoryId : (widget.categories.isEmpty ? '' : widget.categories.first.id),
              decoration: InputDecoration(labelText: context.tr('restaurants_m_item_category'), border: const OutlineInputBorder(), isDense: true),
              items: [
                if (widget.categories.isEmpty) DropdownMenuItem(value: '', child: Text(context.tr('restaurants_menu_other'))),
                for (final cat in widget.categories) DropdownMenuItem(value: cat.id, child: Text(cat.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v ?? ''),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('restaurants_m_item_available'), style: TextStyle(fontSize: 13, color: c.ink)),
              value: _available,
              onChanged: (v) => setState(() => _available = v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.brandInk,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('restaurants_m_save'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
