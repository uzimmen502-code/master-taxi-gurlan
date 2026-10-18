// Ресторан панели — «Меню» (§12.8): категориялар, таомлар, «Бор/Йўқ»,
// «Бугунгача тугади», расм. Ёзиш — тўғридан-тўғри Firestore (rules whitelist).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../home/widgets/ava_section.dart';
import '../data/restaurants_repository.dart';
import '../domain/menu_category_choice.dart';
import '../domain/menu_category_suggestions.dart';
import '../domain/restaurant_models.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;
import 'menu_category_dialog.dart';
import 'menu_item_form_screen.dart';

class MerchantMenuTab extends StatefulWidget {
  const MerchantMenuTab({super.key, required this.restaurant, required this.repository});

  final Restaurant restaurant;
  final RestaurantsRepository repository;

  @override
  State<MerchantMenuTab> createState() => _MerchantMenuTabState();
}

class _MerchantMenuTabState extends State<MerchantMenuTab> {
  String? _selectedCategory; // null — барчаси

  String get _rid => widget.restaurant.id;

  // Оқимлар бир марта очилади (ҳар rebuild'да янги listener эмас).
  late final Stream<List<MenuCategory>> _cats = widget.repository.watchCategories(_rid);
  late final Stream<List<MenuItem>> _items = widget.repository.watchMenu(_rid);

  Future<void> _guard(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(restaurantsErrorText(context, e)), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _editCategory({MenuCategory? existing, required List<MenuCategory> cats}) async {
    final name = await promptMenuCategoryName(
      context,
      existing: existing,
      categories: cats,
      homeCook: widget.restaurant.isHomeCook,
    );
    if (name == null || !mounted) return;
    // Янги категория бир хил номда иккинчи марта яратилмайди — мавжудини
    // танлаймиз (қайта номлашда эганинг ўз танлови тегилмайди).
    final same = existing == null ? MenuCategoryChoice.findByName(cats, name) : null;
    if (same != null) {
      setState(() => _selectedCategory = same.id);
      return;
    }
    await _guard(() => widget.repository.upsertCategory(_rid, id: existing?.id, name: name, sort: existing?.sort ?? cats.length));
  }

  bool _starterBusy = false;

  /// «Тайёр бўлимларни қўшиш»: 3 та бошланғич бўлим (эга тугмани босгандагина;
  /// қўшилгач номини ўзгартириш/ўчириш мумкин). Қўш босишдан ҳимоя — `_starterBusy`.
  Future<void> _addStarter(List<MenuCategory> cats) async {
    if (_starterBusy) return;
    setState(() => _starterBusy = true);
    final names = MenuCategorySuggestions.missingNames(
      keys: MenuCategorySuggestions.starterKeysFor(homeCook: widget.restaurant.isHomeCook),
      name: (k) => context.tr(MenuCategorySuggestions.textKey(k)),
      existing: cats,
    );
    try {
      await _guard(() async {
        var sort = cats.length;
        for (final n in names) {
          await widget.repository.upsertCategory(_rid, name: n, sort: sort++);
        }
      });
    } finally {
      if (mounted) setState(() => _starterBusy = false);
    }
  }

  Future<void> _deleteCategory(MenuCategory cat) async {
    // Категориядаги таомлар ўчмайди — «Бошқалар»га ўтади (репозиторий).
    final ok = await _confirm(context.tr('restaurants_m_delete_category_confirm'));
    if (!ok) return;
    await _guard(() => widget.repository.deleteCategory(_rid, cat.id));
    if (_selectedCategory == cat.id) setState(() => _selectedCategory = null);
  }

  Future<bool> _confirm(String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('restaurants_m_delete'))),
        ],
      ),
    );
    return ok == true;
  }

  void _openItemForm(List<MenuCategory> cats, {MenuItem? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MenuItemFormScreen(
          restaurantId: _rid,
          categories: cats,
          existing: existing,
          initialCategoryId: _selectedCategory,
          homeCook: widget.restaurant.isHomeCook,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return StreamBuilder<List<MenuCategory>>(
      stream: _cats,
      builder: (context, catSnap) {
        final cats = catSnap.data ?? const <MenuCategory>[];
        return StreamBuilder<List<MenuItem>>(
          stream: _items,
          builder: (context, itemSnap) {
            if ((catSnap.connectionState == ConnectionState.waiting && !catSnap.hasData) ||
                (itemSnap.connectionState == ConnectionState.waiting && !itemSnap.hasData)) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = (itemSnap.data ?? const <MenuItem>[])
                .where((m) => _selectedCategory == null || m.categoryId == _selectedCategory)
                .toList(growable: false);
            return Column(
              children: [
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    children: [
                      ChoiceChip(
                        label: Text(context.tr('home_section_see_all')),
                        selected: _selectedCategory == null,
                        onSelected: (_) => setState(() => _selectedCategory = null),
                      ),
                      for (final cat in cats) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onLongPress: () => showModalBottomSheet<void>(
                            context: context,
                            builder: (ctx) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.edit_outlined),
                                    title: Text(ctx.tr('restaurants_m_rename')),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _editCategory(existing: cat, cats: cats);
                                    },
                                  ),
                                  ListTile(
                                    leading: Icon(Icons.delete_outline, color: c.danger),
                                    title: Text(ctx.tr('restaurants_m_delete'), style: TextStyle(color: c.danger)),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _deleteCategory(cat);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          child: ChoiceChip(
                            label: Text(cat.name),
                            selected: _selectedCategory == cat.id,
                            onSelected: (_) => setState(() => _selectedCategory = cat.id),
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 16),
                        label: Text(context.tr('restaurants_m_add_category')),
                        onPressed: () => _editCategory(cats: cats),
                      ),
                    ],
                  ),
                ),
                if (cats.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Container(
                      key: const ValueKey('category-empty-hint'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr('restaurants_m_cat_empty_hint'), style: TextStyle(fontSize: 12, color: c.ink2)),
                          const SizedBox(height: 8),
                          FilledButton.tonal(
                            key: const ValueKey('category-starter'),
                            onPressed: _starterBusy ? null : () => _addStarter(cats),
                            child: Text(context.tr('restaurants_m_cat_starter')),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: AvaNoticeRow(text: context.tr('restaurants_m_no_items'), icon: Icons.restaurant_menu_rounded, color: c.ink3),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, i) => _ItemTile(
                            item: items[i],
                            categoryName: cats.where((x) => x.id == items[i].categoryId).map((x) => x.name).firstOrNull ?? '',
                            onEdit: () => _openItemForm(cats, existing: items[i]),
                            onToggle: (v) => _guard(() => widget.repository.setItemAvailability(_rid, items[i].id, available: v, stopUntil: null)),
                            onStopToday: () {
                              final now = DateTime.now();
                              final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
                              _guard(() => widget.repository.setItemAvailability(_rid, items[i].id, available: true, stopUntil: end));
                            },
                            onDelete: () async {
                              if (await _confirm(context.tr('restaurants_m_delete_confirm'))) {
                                await _guard(() => widget.repository.deleteMenuItem(_rid, items[i].id));
                              }
                            },
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openItemForm(cats),
                      style: FilledButton.styleFrom(backgroundColor: c.brand, foregroundColor: c.brandInk),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.tr('restaurants_m_add_item')),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.categoryName,
    required this.onEdit,
    required this.onToggle,
    required this.onStopToday,
    required this.onDelete,
  });

  final MenuItem item;
  final String categoryName;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onStopToday;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final stopped = item.available && item.stopUntil != null && item.stopUntil!.isAfter(DateTime.now());
    final photo = item.photoUrl.trim();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: photo.startsWith('http')
                  ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover)
                  : ColoredBox(color: c.surface2, child: Icon(Icons.restaurant_rounded, color: c.ink3)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink)),
                Text(
                  '${formatPrice(item.price)} ${context.tr('sum')}${categoryName.isEmpty ? '' : ' · $categoryName'}'
                  '${stopped ? ' · ${context.tr('restaurants_m_stop_today')}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: stopped ? c.warn : c.ink2),
                ),
              ],
            ),
          ),
          Switch(value: item.available && !stopped, onChanged: onToggle),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  onEdit();
                  break;
                case 'stop':
                  onStopToday();
                  break;
                case 'delete':
                  onDelete();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'edit', child: Text(ctx.tr('restaurants_m_rename'))),
              PopupMenuItem(value: 'stop', child: Text(ctx.tr('restaurants_m_stop_today'))),
              PopupMenuItem(value: 'delete', child: Text(ctx.tr('restaurants_m_delete'), style: TextStyle(color: c.danger))),
            ],
          ),
        ],
      ),
    );
  }
}
