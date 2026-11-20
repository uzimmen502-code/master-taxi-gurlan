import 'package:flutter/material.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_selector.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../domain/sm_offer.dart';
import '../domain/sm_search.dart';
import '../domain/sm_taxonomy.dart';
import '../supermarket_controller.dart';
import '../widgets/sm_widgets.dart';
import 'sm_cart_screen.dart';
import 'sm_category_screen.dart';
import 'sm_group_screen.dart';

/// Категория иконкаси: сервер `icon` калити → Material иконка (номаълум — умумий).
IconData smCategoryIcon(String key) => switch (key) {
      'vegetables' => Icons.eco_outlined,
      'fruits' => Icons.apple_outlined,
      'meat' => Icons.kebab_dining_outlined,
      'dairy' => Icons.egg_outlined,
      'bakery' => Icons.bakery_dining_outlined,
      'grocery' => Icons.rice_bowl_outlined,
      'drinks' => Icons.local_drink_outlined,
      'household' => Icons.cleaning_services_outlined,
      'sweets' => Icons.cake_outlined,
      _ => Icons.local_grocery_store_outlined,
    };

/// Супермаркетни очиш (илдиз маршрут номи билан — «Каталог» шу ергача қайтаради).
/// [initialGroupId] — юклангач шу гуруҳ экрани очилади (Аралашдаги AVA маҳсулотидан келганда).
Future<void> openSupermarket(BuildContext context, {SupermarketController? controller, String? initialGroupId}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    settings: const RouteSettings(name: kSmHomeRouteName),
    builder: (_) => SupermarketHomeScreen(controller: controller, initialGroupId: initialGroupId),
  ));
}

void smOpenCart(BuildContext context, SupermarketController controller) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SmCartScreen(controller: controller)));
}

/// 1-экран: Супермаркет бош саҳифаси (эга 2026-11-20).
class SupermarketHomeScreen extends StatefulWidget {
  const SupermarketHomeScreen({super.key, this.controller, this.pickArea, this.initialGroupId});

  final String? initialGroupId;

  /// Тест учун; бўлмаса — янги контроллер (Firebase).
  final SupermarketController? controller;

  /// Тест учун; бўлмаса — мавжуд [GeoAreaPickScreen].
  final Future<GeoArea?> Function(BuildContext context)? pickArea;

  @override
  State<SupermarketHomeScreen> createState() => _SupermarketHomeScreenState();
}

class _SupermarketHomeScreenState extends State<SupermarketHomeScreen> {
  late final SupermarketController _c = widget.controller ?? SupermarketController();
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _c.load().then((_) => _openInitialGroup());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialGroup());
    }
  }

  void _openInitialGroup() {
    final id = widget.initialGroupId;
    if (!mounted || id == null) return;
    final g = _c.taxonomy.group(id);
    if (g == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SmGroupScreen(controller: _c, group: g)));
  }

  @override
  void dispose() {
    _search.dispose();
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  Future<void> _editArea() async {
    final picked = await (widget.pickArea?.call(context) ??
        Navigator.of(context).push<GeoArea>(MaterialPageRoute(builder: (_) => const GeoAreaPickScreen())));
    if (picked != null && !picked.isEmpty) {
      _c.deliveryArea = picked;
      // Рухсат ва вақтлар туманга боғлиқ — сервердан қайта (getSupermarketAccess({districtId})).
      await _c.refreshAccessFor(picked.districtId);
    }
  }

  void _soon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr('sm_soon'))));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('sm_title')),
        actions: [SmCartAction(controller: _c, onTap: () => smOpenCart(context, _c))],
      ),
      bottomNavigationBar: SmBottomBar(controller: _c, onCart: () => smOpenCart(context, _c)),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          if (_c.loading && _c.taxonomy.categories.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_c.loadErrorKey != null && _c.taxonomy.categories.isEmpty) {
            return _ErrorView(textKey: _c.loadErrorKey!, onRetry: _c.load);
          }
          final lang = context.contentLang;
          return ListView(
            key: const PageStorageKey('sm_home_list'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _AddressLine(area: _c.deliveryArea, onEdit: _editArea),
              if (!_c.access.allowed) ...[
                const SizedBox(height: 8),
                _InfoBanner(text: context.tr('sm_not_available_here')),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('sm_search'),
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: context.tr('sm_search_hint'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.tr('sm_clear'),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() {
                            _search.clear();
                            _query = '';
                          }),
                        ),
                  filled: true,
                  fillColor: c.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.line)),
                  enabledBorder:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.line)),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _EntryChip(id: 'products', label: context.tr('sm_chip_products'), active: true, onTap: () {}),
                  _EntryChip(id: 'quick', label: context.tr('sm_chip_quick'), soon: true, onTap: _soon),
                  _EntryChip(id: 'weekly', label: context.tr('sm_chip_weekly'), soon: true, onTap: _soon),
                ],
              ),
              const SizedBox(height: 16),
              if (_query.trim().isNotEmpty)
                ..._searchResults(context, lang)
              else
                for (final cat in _c.taxonomy.categories)
                  if (_c.visibleGroups(cat).isNotEmpty) ...[
                    _CategoryCard(
                      category: cat,
                      lang: lang,
                      groupCount: _c.visibleGroups(cat).length,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => SmCategoryScreen(controller: _c, category: cat),
                      )),
                    ),
                    const SizedBox(height: 10),
                  ],
            ],
          );
        },
      ),
    );
  }

  List<Widget> _searchResults(BuildContext context, String lang) {
    final groups = smSearchGroups(_c.taxonomy, _c.offersByGroup, _query);
    if (groups.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(context.tr('sm_search_none'),
              key: const ValueKey('sm_search_none'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
        ),
      ];
    }
    return [
      for (final g in groups) ...[
        SmGroupRow(controller: _c, group: g, lang: lang),
        const SizedBox(height: 8),
      ],
    ];
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({required this.area, required this.onEdit});

  final GeoArea area;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final label = area.label.trim();
    return InkWell(
      key: const ValueKey('sm_address_line'),
      borderRadius: BorderRadius.circular(12),
      onTap: onEdit,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Icon(Icons.place_outlined, color: c.brandText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${context.tr('sm_delivery_to')}: ${label.isEmpty ? context.tr('sm_address_choose') : label}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: c.ink),
              ),
            ),
            Icon(Icons.edit_outlined, size: 20, color: c.ink2),
          ],
        ),
      ),
    );
  }
}

class _EntryChip extends StatelessWidget {
  const _EntryChip({required this.id, required this.label, required this.onTap, this.active = false, this.soon = false});

  final String id;
  final String label;
  final bool active;
  final bool soon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Material(
      key: ValueKey('sm_chip_$id'),
      color: active ? c.brand : c.surface,
      shape: StadiumBorder(side: BorderSide(color: active ? c.brand : c.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600, color: active ? c.brandInk : c.ink)),
                ),
                if (soon) ...[
                  const SizedBox(width: 6),
                  Text(context.tr('sm_soon_badge'), style: TextStyle(fontSize: 12, color: c.ink2)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.lang, required this.groupCount, required this.onTap});

  final SmCategory category;
  final String lang;
  final int groupCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Material(
      key: ValueKey('sm_category_${category.id}'),
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(smCategoryIcon(category.icon), color: c.brandText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.name(lang),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                    const SizedBox(height: 2),
                    Text(context.tr('sm_groups_count').replaceAll('{n}', '$groupCount'),
                        style: TextStyle(fontSize: 14, color: c.ink2)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Гуруҳ қатори (категория ва қидирув натижаси учун умумий): расм, ном, навлар, «… дан».
class SmGroupRow extends StatelessWidget {
  const SmGroupRow({super.key, required this.controller, required this.group, required this.lang});

  final SupermarketController controller;
  final SmGroup group;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final offers = controller.offersByGroup[group.id] ?? const <SmOffer>[];
    final cheapest = smCheapestActivePrice(offers);
    final sorted = smSortOffersAsc(offers);
    final image = sorted.map((o) => o.imageUrl).firstWhere((u) => u.isNotEmpty, orElse: () => '');
    final varieties = smVarieties(offers)
        .where((v) => v.names.isNotEmpty)
        .map((v) => localizedName(v.names, lang))
        .take(3)
        .join(', ');
    return Material(
      key: ValueKey('sm_group_${group.id}'),
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SmGroupScreen(controller: controller, group: group),
        )),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SmThumb(url: image),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name(lang),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                    if (varieties.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(varieties,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.ink2)),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      cheapest == null
                          ? context.tr('sm_out_of_stock')
                          : context
                              .tr('sm_price_from')
                              .replaceAll('{price}', smPricePerUnit(context, cheapest, group.unit)),
                      key: ValueKey('sm_group_price_${group.id}'),
                      style: TextStyle(
                        fontSize: cheapest == null ? 14 : 17,
                        fontWeight: cheapest == null ? FontWeight.w400 : FontWeight.w700,
                        color: cheapest == null ? c.ink2 : c.ink,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      key: const ValueKey('sm_not_available'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(fontSize: 15, color: c.ink)),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.textKey, required this.onRetry});

  final String textKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr(textKey), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(context.tr('sm_retry'))),
          ],
        ),
      ),
    );
  }
}

/// Кўрсатиш учун: «12 000 сўм» (formatMoney қайта экспорт — экранлар бир манбадан).
String smMoney(int v) => formatMoney(v);
