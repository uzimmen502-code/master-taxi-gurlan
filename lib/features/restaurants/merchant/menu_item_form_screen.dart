// Таом қўшиш/таҳрирлаш: ном, нарх (бутун сўм — қадоқлаш ҳақи ЙЎҚ, D-REST-28), тавсиф,
// категория (тизим таклифи + ўзи танлайди, D-REST-29), расм (`restaurant_images/{rid}/`), «Бор/Йўқ».

import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../data/restaurants_repository.dart';
import '../../tv_market/models/tv_clip.dart';
import '../domain/dish_facts.dart';
import '../domain/menu_category_choice.dart';
import '../domain/menu_category_names.dart';
import '../domain/menu_category_suggestions.dart';
import '../domain/restaurant_models.dart';
import '../services/restaurant_storage_service.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;
import 'dish_facts_editor.dart';
import 'qty_tiers_editor.dart';
import 'dish_video_tile.dart';
import 'menu_category_dialog.dart';
import 'menu_category_picker.dart';

class MenuItemFormScreen extends StatefulWidget {
  const MenuItemFormScreen({
    super.key,
    required this.restaurantId,
    required this.categories,
    required this.repository,
    this.existing,
    this.initialCategoryId,
    this.homeCook = false,
    this.storage,
    this.ownerPhone,
    this.restaurantApproved = true,
    this.videoLoader,
    this.videoPublisher,
    this.videoDeleter,
    this.videoOpener,
  });

  final String restaurantId;
  final List<MenuCategory> categories;
  final RestaurantsRepository repository;
  final MenuItem? existing;
  final String? initialCategoryId;

  /// Категория номи таклифлари рўйхати учун (уй ошпази / кафе).
  final bool homeCook;
  final RestaurantStorageService? storage;

  /// Ресторан эгаси телефони — берилса расм ёнида ихтиёрий «Видео» катаги кўринади
  /// (`DishVideoTile`). Берилмаса (эски чақирувлар) катак йўқ.
  final String? ownerPhone;
  final bool restaurantApproved;

  /// Тест учун алмаштириладиган видео боғловчилари (ҳақиқийси — умумий қатлам).
  final Future<List<TvClip>> Function(String itemId)? videoLoader;
  final Future<bool> Function(String itemId)? videoPublisher;
  final Future<void> Function(TvClip clip)? videoDeleter;
  final void Function(TvClip clip)? videoOpener;

  @override
  State<MenuItemFormScreen> createState() => _MenuItemFormScreenState();
}

class _MenuItemFormScreenState extends State<MenuItemFormScreen> {
  late final RestaurantStorageService _storage = widget.storage ?? RestaurantStorageService();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _price = TextEditingController(text: widget.existing == null ? '' : '${widget.existing!.price}');
  late final _desc = TextEditingController(text: widget.existing?.description ?? '');
  // Форма ичида яратилган категория ҳам рўйхатга тушсин (экран очилгандаги
  // `widget.categories` — қотган нусха).
  late final List<MenuCategory> _cats = List.of(widget.categories);
  late String _categoryId = MenuCategoryChoice.initial(
    isEdit: widget.existing != null,
    existingCategoryId: widget.existing?.categoryId,
    filterCategoryId: widget.initialCategoryId,
    categories: widget.categories,
  );
  late bool _available = widget.existing?.available ?? true;

  // Таом ВИДЕО учун аввал сақланиши мумкин (клип таом ID'сига боғланади) — шундан кейинги
  // сақлашлар ШУ ҳужжатни янгилайди, расм қайта юкланмайди, тартиб ўзгармайди.
  late String? _savedId = widget.existing?.id;
  late String _photoUrl = widget.existing?.photoUrl ?? '';
  late final int _sort = widget.existing?.sort ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  // Сотувчи киритган ихтиёрий фактлар (порция, КБЖУ, кухна, теглар) — таҳрирда мавжуд қиймат.
  late DishFacts _facts = widget.existing?.facts ?? DishFacts.empty;
  bool _showFactErrors = false;
  // Миқдорга чегирма (D-REST-25): таҳрирда мавжуд поғоналар; ўзгарганда редактор янгилайди.
  late QtyTiersDraft _tiers = QtyTiersDraft(widget.existing?.qtyTiers ?? const []);
  bool _showTierErrors = false;
  bool _showItemErrors = false;
  XFile? _picked;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _price, _desc]) {
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

  /// Форманинг ўзидан янги категория яратиш: янги ошпазда ҳали бирорта
  /// категория йўқ — аввал «Меню» табига қайтиб яратиш шарт эмас.
  Future<void> _createCategory() async {
    final name = await promptMenuCategoryName(context, categories: _cats, homeCook: widget.homeCook);
    if (!mounted) return;
    if (name == null) return;
    final same = MenuCategoryChoice.findByName(_cats, name);
    if (same != null) {
      setState(() => _categoryId = same.id);
      return;
    }
    try {
      final sort = _cats.length;
      final id = await widget.repository.upsertCategory(widget.restaurantId, name: name, sort: sort);
      if (!mounted) return;
      setState(() {
        _cats.add(MenuCategory(id: id, name: name, sort: sort));
        _categoryId = id;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(restaurantsErrorText(context, e)), backgroundColor: Colors.red.shade700),
      );
    }
  }

  /// Танланган категориянинг ҳақиқий id'си. Тизим таклифи танланган бўлса — бўлим ШУ ЕРДА (таом
  /// сақланаётганда) яратилади: фақат кўриб чиқиш ҳужжат яратмайди. Шу ном билан категория
  /// ўрталикда пайдо бўлган бўлса (бошқа қурилма) — такрор яратилмайди.
  Future<String> _resolveCategoryId() async {
    final key = MenuCategoryChoice.suggestedKey(_categoryId);
    if (key == null) return MenuCategoryChoice.known(_categoryId, _cats);
    final name = MenuCategoryNames.presetName(key, context.contentLang);
    final same = MenuCategoryChoice.findByName(_cats, name);
    if (same != null) {
      _categoryId = same.id;
      return same.id;
    }
    final sort = _cats.length;
    final id = await widget.repository.upsertCategory(widget.restaurantId, name: name, sort: sort);
    _cats.add(MenuCategory(id: id, name: name, sort: sort));
    _categoryId = id; // кейинги сақлашда такрор яратилмасин
    return id;
  }

  /// Таомни сақлайди (яратади ёки янгилайди) ва ID қайтаради; текширув ёки сақлаш хато берса —
  /// `null` (хабар шу ерда кўрсатилади). Видео катаги ҳам шуни чақиради: янги таомга клип
  /// боғлаш учун таом аввал яратилиши керак.
  Future<String?> _persist() async {
    if (_saving) return null;
    final name = _name.text.trim();
    final price = int.tryParse(_price.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    if (name.isEmpty || price <= 0) {
      setState(() => _showItemErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('restaurants_m_err_item')), backgroundColor: Colors.red.shade700),
      );
      return null;
    }
    // Фактлар ихтиёрий, лекин киритилган бўлса тўғри бўлиши шарт — хатоли карточкалар очилади.
    if (_facts.validate().isNotEmpty) {
      setState(() => _showFactErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('restaurants_m_dish_err_fix')), backgroundColor: Colors.red.shade700),
      );
      return null;
    }
    // Миқдорга чегирма ихтиёрий, лекин киритилган бўлса тўғри бўлиши шарт (асосий нархдан кам, тартибли).
    if (_tiers.errorsFor(price).isNotEmpty) {
      setState(() => _showTierErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('restaurants_m_tiers_err_fix')), backgroundColor: Colors.red.shade700),
      );
      return null;
    }
    setState(() => _saving = true);
    try {
      if (_picked != null) {
        _photoUrl = await _storage.uploadImage(restaurantId: widget.restaurantId, image: _picked!, kind: 'item');
        _picked = null; // юкланди — кейинги сақлашда қайта юкланмайди
      }
      final categoryId = await _resolveCategoryId();
      final id = await widget.repository.upsertMenuItem(
        widget.restaurantId,
        id: _savedId,
        name: name,
        price: price,
        description: _desc.text.trim(),
        photoUrl: _photoUrl,
        categoryId: categoryId,
        sort: _sort,
        available: _available,
        stopUntil: _available ? widget.existing?.stopUntil : null,
        facts: _facts,
        qtyTiers: _tiers.tiers,
      );
      _savedId = id;
      return id;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(restaurantsErrorText(context, e)), backgroundColor: Colors.red.shade700),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final id = await _persist();
    if (id != null && mounted) Navigator.of(context).pop();
  }
  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final existingPhoto = _photoUrl.trim();
    const contentMaxWidth = 640.0;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width > contentMaxWidth + 32 ? (width - contentMaxWidth) / 2 : 16.0;
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
          // Кенг экранда (веб) форма ўқилувчан кенгликда (640) марказда туради.
          padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 24),
          children: [
            LayoutBuilder(
              builder: (context, cons) {
                final showVideo = widget.ownerPhone != null;
                // Расм ва видео катаклари ёнма-ён сиғиши учун (320 px да ҳам): 140 дан катта эмас.
                final size = showVideo ? math.min(140.0, (cons.maxWidth - 12) / 2) : 140.0;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Semantics(
                      button: true,
                      label: context.tr('restaurants_m_item_photo'),
                      excludeSemantics: true,
                      onTap: _pickPhoto,
                      child: InkWell(
                      onTap: _pickPhoto,
                      borderRadius: BorderRadius.circular(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: size,
                          height: size,
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
                    if (showVideo) ...[
                      const SizedBox(width: 12),
                      DishVideoTile(
                        restaurantId: widget.restaurantId,
                        ownerPhone: widget.ownerPhone!,
                        restaurantApproved: widget.restaurantApproved,
                        itemId: _savedId,
                        ensureSaved: _persist,
                        size: size,
                        loader: widget.videoLoader,
                        publisher: widget.videoPublisher,
                        deleter: widget.videoDeleter,
                        opener: widget.videoOpener,
                      ),
                    ],
                  ],
                );
              },
            ),
            if (widget.ownerPhone != null && _savedId == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  context.tr('restaurants_m_dish_video_save_hint'),
                  textAlign: TextAlign.center,
                  style: AvaText.caption.copyWith(color: c.ink3),
                ),
              ),            const SizedBox(height: 14),
            TextField(
              controller: _name,
              maxLength: 80,
              onChanged: (_) {
                if (_showItemErrors) setState(() {});
              },
              decoration: InputDecoration(
                labelText: context.tr('restaurants_m_item_name'),
                errorText: _showItemErrors && _name.text.trim().isEmpty ? context.tr('restaurants_m_err_item_name') : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) {
                if (_showItemErrors) setState(() {});
              },
              decoration: InputDecoration(
                labelText: context.tr('restaurants_m_item_price'),
                errorText: _showItemErrors && (int.tryParse(_price.text.replaceAll(RegExp(r'\D'), '')) ?? 0) <= 0
                    ? context.tr('restaurants_m_err_item_price')
                    : null,
                suffixText: context.tr('sum'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            QtyTiersEditor(
              initial: widget.existing?.qtyTiers ?? const [],
              priceController: _price,
              showErrors: _showTierErrors,
              onChanged: (d) => _tiers = d,
            ),
            const SizedBox(height: 8),
            TextField(controller: _desc, maxLength: 500, maxLines: 2, decoration: InputDecoration(labelText: context.tr('restaurants_m_item_desc'), border: const OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 8),
            MenuCategoryPicker(
              categories: _cats,
              suggestions: MenuCategorySuggestions.missingEntries(
                keys: MenuCategorySuggestions.keysFor(homeCook: widget.homeCook),
                lang: context.contentLang,
                existing: _cats,
              ),
              selectedId: MenuCategoryChoice.known(_categoryId, _cats),
              lang: context.contentLang,
              onSelected: (id) => setState(() => _categoryId = id),
              onCreateOwn: _createCategory,
            ),
            DishFactsEditor(
              initial: _facts,
              priceController: _price,
              showErrors: _showFactErrors,
              onChanged: (f) => _facts = f,
              loadCuisines: widget.repository.listCuisines,
              addCuisine: (name, group) =>
                  widget.repository.addCuisine(restaurantId: widget.restaurantId, name: name, group: group),
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
