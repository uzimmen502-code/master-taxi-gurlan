import 'dart:async';

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/catalog_search.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../bread/services/bread_image_storage.dart';
import '../../../models/platform_product.dart';
import '../../../repositories/platform_products_repository.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_market_service.dart';
import '../utils/clipboard_paste_image.dart';
import '../utils/web_image_compress.dart';

/// Админ: платформа дўкони каталоги.
class PlatformProductsAdminScreen extends StatefulWidget {
  const PlatformProductsAdminScreen({super.key});

  @override
  State<PlatformProductsAdminScreen> createState() =>
      _PlatformProductsAdminScreenState();
}

class _PlatformProductsAdminScreenState
    extends State<PlatformProductsAdminScreen> {
  final _repo = PlatformProductsRepository();
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _selected = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : AppColors.button,
      ),
    );
  }

  List<PlatformProduct> _filter(List<PlatformProduct> all) {
    final q = _query;
    var list = all.where((p) {
      return CatalogSearch.matches(q, [
        p.name,
        p.description,
        p.unit,
        '${p.price}',
        p.id,
        p.active ? 'фаол' : 'нофаол',
        p.showInMarket ? 'бозор' : '',
        p.featuredOnHome ? 'витрина' : '',
        p.isFood ? 'озиқ' : '',
        p.isNonFood ? 'но-озиқ' : '',
        p.isKindSet ? '' : 'белгиланмаган',
      ]);
    }).toList();
    if (CatalogSearch.normalize(q).isNotEmpty) {
      list.sort((a, b) {
        final byScore = CatalogSearch.scoreProduct(b, q)
            .compareTo(CatalogSearch.scoreProduct(a, q));
        if (byScore != 0) return byScore;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    }
    return list;
  }

  List<PlatformProduct> _findNameDuplicates(
    List<PlatformProduct> all,
    String name, {
    String? exceptId,
  }) {
    final n = CatalogSearch.normalize(name);
    if (n.isEmpty) return const [];
    return all
        .where((p) {
          if (exceptId != null && p.id == exceptId) return false;
          return CatalogSearch.normalize(p.name) == n;
        })
        .toList(growable: false);
  }

  List<PlatformProduct> _latestCatalog = const [];

  Future<void> _openEdit(
    List<PlatformProduct> catalog, [
    PlatformProduct? existing,
  ]) async {
    final result = await showDialog<PlatformProduct>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditDialog(
        existing: existing,
        catalog: catalog,
      ),
    );
    if (result == null || !mounted) return;

    final dups = _findNameDuplicates(
      catalog,
      result.name,
      exceptId: existing?.id,
    );
    if (dups.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Такрорий ном'),
          content: Text(
            '«${result.name}» номли маҳсулот аллақачон бор '
            '(${dups.length} та). Барибир сақлайсизми?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Бекор'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сақлаш'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    try {
      if (existing == null) {
        await _repo.create(result);
        _toast('Қўшилди');
      } else {
        await _repo.update(result);
        _toast('Сақланди');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('Хато: $e', error: true);
    }
  }

  static const _bulkMax = 20;

  String _nameFromFilename(String filename) {
    var n = filename.trim();
    final slash = n.replaceAll('\\', '/').lastIndexOf('/');
    if (slash >= 0) n = n.substring(slash + 1);
    final dot = n.lastIndexOf('.');
    if (dot > 0) n = n.substring(0, dot);
    n = n
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return n;
  }

  Future<void> _openBulkAdd() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (res == null || res.files.isEmpty || !mounted) return;

      final readable = <_BulkImageSeed>[];
      for (final f in res.files) {
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final lower = f.name.toLowerCase();
        final mime = lower.endsWith('.png')
            ? 'image/png'
            : lower.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg';
        readable.add(
          _BulkImageSeed(
            bytes: bytes,
            mime: mime,
            name: _nameFromFilename(f.name),
          ),
        );
        if (readable.length >= _bulkMax) break;
      }
      if (readable.isEmpty) {
        _toast('Файллар ўқилмади — кичикроқ JPG/PNG танланг.', error: true);
        return;
      }
      if (res.files.length > _bulkMax) {
        _toast('Фақат биринчи $_bulkMax та расм олинди');
      }

      final created = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BulkAddDialog(
          seeds: readable,
          repo: _repo,
        ),
      );
      if (!mounted || created == null) return;
      if (created > 0) {
        _toast('$created та маҳсулот қўшилди');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('Хато: $e', error: true);
    }
  }

  Future<void> _delete(PlatformProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ўчириш'),
        content: Text('«${p.name}» ўчирилсинми?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ҳа'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(p.id);
      if (!mounted) return;
      _toast('Ўчирилди');
    } catch (e) {
      if (!mounted) return;
      _toast('Хато: $e', error: true);
    }
  }

  Future<void> _classifySelected(String kind) async {
    if (_selected.isEmpty) return;
    final isNonFood = kind == PlatformProduct.kindNonFood;
    final nSel = _selected.length;
    final nRest = isNonFood
        ? _latestCatalog.where((p) => !_selected.contains(p.id)).length
        : 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isNonFood ? 'Но-озиқ + қолганлари Озиқ' : 'Озиқ қилиш'),
        content: Text(
          isNonFood
              ? '$nSel та → Но-озиқ.\n'
                  'Қолган $nRest та → Озиқ (автомат).'
              : '$nSel та маҳсулот «Озиқ» деб белгилансинми?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ҳа'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (isNonFood) {
        await _repo.setNonFoodSelectedRestFood(
          nonFoodIds: _selected,
          allIds: _latestCatalog.map((p) => p.id),
        );
        if (!mounted) return;
        setState(() => _selected.clear());
        _toast(
          '$nSel та Но-озиқ, $nRest та Озиқ қилинди',
        );
      } else {
        await _repo.setGoodsKindBatch(_selected, kind);
        if (!mounted) return;
        setState(() => _selected.clear());
        _toast('$nSel та маҳсулот «Озиқ» қилинди');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('Хато: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      floatingActionButton: null,
      body: Column(
        children: [
          const _PlatformFeaturedAutoBar(),
          const _PlatformDeliveryFeeBar(),
          if (_selected.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Row(
                children: [
                  Text(
                    'Танланган: ${_selected.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _selected.clear()),
                    child: const Text('Бекор'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: () =>
                        _classifySelected(PlatformProduct.kindFood),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Озиқ'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: () =>
                        _classifySelected(PlatformProduct.kindNonFood),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade700,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Но-озиқ (+қолганлари Озиқ)'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 640;
                final search = TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Қидирув: ном, нарх, тавсиф, ID…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Тозалаш',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                );
                final actions = [
                  FilledButton.icon(
                    onPressed: () => _openBulkAdd(),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                    icon: const Icon(Icons.library_add_outlined, size: 20),
                    label: const Text('Кўп қўшиш'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openEdit(_latestCatalog),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.button,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Маҳсулот'),
                  ),
                ];
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      search,
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: actions,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 8),
                    ...[
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        actions[i],
                      ],
                    ],
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<List<PlatformProduct>>(
              stream: _repo.watchAll(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data ?? const <PlatformProduct>[];
                _latestCatalog = all;
                // Ажратилган ID лар танловда қолмасин (катакча яширилади).
                if (_selected.isNotEmpty) {
                  final unclassifiedIds = <String>{
                    for (final p in all)
                      if (!p.isKindSet) p.id,
                  };
                  final stale = _selected
                      .where((id) => !unclassifiedIds.contains(id))
                      .toList(growable: false);
                  if (stale.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() => _selected.removeAll(stale));
                    });
                  }
                }
                final items = _filter(all);
                if (all.isEmpty) {
                  return const Center(
                    child: Text('Каталог бўш — маҳсулот қўшинг'),
                  );
                }
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      '«$_query» бўйича топилмади',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  );
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _query.trim().isEmpty
                              ? 'Жами: ${all.length}'
                              : 'Топилди: ${items.length} / ${all.length}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          final cols = w >= 1500
                              ? 5
                              : w >= 1200
                                  ? 4
                                  : w >= 900
                                      ? 3
                                      : w >= 600
                                          ? 2
                                          : 1;
                          return GridView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(12, 8, 12, 24),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              mainAxisExtent: 76,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, i) {
                              final p = items[i];
                              final canSelect = !p.isKindSet;
                              final selected =
                                  canSelect && _selected.contains(p.id);
                              return _ProductTile(
                                index: i + 1,
                                product: p,
                                selected: selected,
                                showSelect: canSelect,
                                onToggleSelect: () {
                                  if (!canSelect) return;
                                  setState(() {
                                    if (selected) {
                                      _selected.remove(p.id);
                                    } else {
                                      _selected.add(p.id);
                                    }
                                  });
                                },
                                onTap: () => _openEdit(all, p),
                                onMenu: (v) async {
                                  if (v == 'edit') {
                                    await _openEdit(all, p);
                                  } else if (v == 'toggle') {
                                    await _repo.setActive(p.id, !p.active);
                                  } else if (v == 'delete') {
                                    await _delete(p);
                                  } else if (v == 'food') {
                                    await _repo.setGoodsKindBatch(
                                      [p.id],
                                      PlatformProduct.kindFood,
                                    );
                                    if (mounted) {
                                      setState(() => _selected.remove(p.id));
                                    }
                                  } else if (v == 'non_food') {
                                    await _repo.setNonFoodSelectedRestFood(
                                      nonFoodIds: [p.id],
                                      allIds: all.map((e) => e.id),
                                    );
                                    if (mounted) {
                                      setState(() => _selected.clear());
                                      _toast(
                                        'Но-озиқ қилинди; қолганлари Озиқ',
                                      );
                                    }
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// `settings/app.platformFeaturedAuto` — ҚЎЛДА / АВТО витрина.
class _PlatformFeaturedAutoBar extends StatefulWidget {
  const _PlatformFeaturedAutoBar();

  @override
  State<_PlatformFeaturedAutoBar> createState() =>
      _PlatformFeaturedAutoBarState();
}

class _PlatformFeaturedAutoBarState extends State<_PlatformFeaturedAutoBar> {
  bool _busy = false;

  Future<void> _setAuto(bool enabled) async {
    final adminPhone = context.read<AdminAuthService>().phoneDigits ?? '';
    if (adminPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin телефон топилмади — қайта киринг'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AdminMarketService>().setPlatformFeaturedAuto(
            adminPhone: adminPhone,
            enabled: enabled,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .snapshots(),
      builder: (context, snap) {
        // Default АВТО (null/absent → true).
        final auto = snap.data?.data()?['platformFeaturedAuto'] != false;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: auto ? Colors.green.shade50 : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: auto ? Colors.green.shade200 : Colors.orange.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                auto ? Icons.flash_on : Icons.admin_panel_settings,
                color: auto ? Colors.green.shade700 : Colors.orange.shade800,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  auto
                      ? 'Витрина АВТО — фаол маҳсулотлар «Тавсия этамиз»да кўринади'
                      : 'Витрина ҚЎЛДА — фақат «Тавсия этамиз» белгиланганлари',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color:
                        auto ? Colors.green.shade900 : Colors.orange.shade900,
                  ),
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                OutlinedButton(
                  onPressed: auto ? () => _setAuto(false) : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                  ),
                  child: const Text('ҚЎЛДА', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: auto ? null : () => _setAuto(true),
                  icon: const Icon(Icons.flash_on, size: 16),
                  label: const Text('АВТО', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.button,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// `settings/app.platformDeliveryFeePercent` — курьер/етказиб бериш ҳақи %.
class _PlatformDeliveryFeeBar extends StatefulWidget {
  const _PlatformDeliveryFeeBar();

  @override
  State<_PlatformDeliveryFeeBar> createState() =>
      _PlatformDeliveryFeeBarState();
}

class _PlatformDeliveryFeeBarState extends State<_PlatformDeliveryFeeBar> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  bool _synced = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final adminPhone = context.read<AdminAuthService>().phoneDigits ?? '';
    if (adminPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin телефон топилмади — қайта киринг'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final raw = _ctrl.text.trim().replaceAll(',', '.');
    final pct = double.tryParse(raw);
    if (pct == null || pct < 0 || pct > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Фоиз 0…100 оралиғида бўлиши керак'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AdminMarketService>().setPlatformDeliveryFeePercent(
            adminPhone: adminPhone,
            percent: pct,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Етказиб бериш ҳақи: $pct% сақланди'),
          backgroundColor: AppColors.button,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final pct = (data?['platformDeliveryFeePercent'] as num?)?.toDouble() ??
            5.0;
        if (!_synced && snap.hasData) {
          _synced = true;
          final text = pct == pct.roundToDouble()
              ? '${pct.round()}'
              : pct.toString();
          if (_ctrl.text != text) {
            _ctrl.text = text;
          }
        }
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.cyan.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.cyan.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.local_shipping_outlined,
                  color: Colors.cyan.shade800, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Етказиб бериш ҳақи = маҳсулот нарҳи × X%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.cyan.shade900,
                      ),
                    ),
                    Text(
                      'Ҳозир: $pct% (мас. 100 000 → '
                      '${formatPrice((100000 * pct / 100).round())} сўм)',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.cyan.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _ctrl,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    suffixText: '%',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.button,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 36),
                  ),
                  child: const Text('Сақлаш', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.index,
    required this.product,
    required this.selected,
    required this.showSelect,
    required this.onToggleSelect,
    required this.onTap,
    required this.onMenu,
  });

  final int index;
  final PlatformProduct product;
  final bool selected;
  /// Фақат `goodsKind` бўш (янги / ажратилмаган) маҳсулотларда катакча.
  final bool showSelect;
  final VoidCallback onToggleSelect;
  final VoidCallback onTap;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final kindLabel = product.isFood
        ? 'озиқ'
        : product.isNonFood
            ? 'но-озиқ'
            : '—';
    final meta = [
      '${formatPrice(product.price)} сўм',
      kindLabel,
      product.active ? 'фаол' : 'нофаол',
      if (product.featuredOnHome) 'витрина',
      if (product.showInMarket) 'бозор',
      product.isUnlimitedStock ? 'лимитсиз' : 'қолдиқ ${product.remaining}',
    ].join(' · ');

    return Material(
      color: selected ? Colors.indigo.shade50 : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        onLongPress: showSelect ? onToggleSelect : null,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? Colors.indigo.shade300 : const Color(0xFFE8ECE8),
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(
            children: [
              if (showSelect)
                Checkbox(
                  value: selected,
                  onChanged: (_) => onToggleSelect(),
                  visualDensity: VisualDensity.compact,
                )
              else
                const SizedBox(width: 8),
              SizedBox(
                width: 22,
                child: Text(
                  '$index',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _Thumb(url: product.coverImageUrl),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                onSelected: onMenu,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Таҳрир'),
                  ),
                  const PopupMenuItem(
                    value: 'food',
                    child: Text('Озиқ қилиш'),
                  ),
                  const PopupMenuItem(
                    value: 'non_food',
                    child: Text('Но-озиқ қилиш'),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(product.active ? 'Нофаол' : 'Фаол'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Ўчириш'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    Widget child = const ColoredBox(
      color: Color(0xFFE8F5E9),
      child: Icon(Icons.storefront, color: AppColors.button),
    );
    if (u.isNotEmpty && isHttpImageUrl(u)) {
      child = CachedNetworkImage(imageUrl: u, fit: BoxFit.cover);
    } else if (u.isNotEmpty && isDataImageUrl(u)) {
      final bytes = decodeDataUrlImageBytes(u);
      if (bytes != null) child = Image.memory(bytes, fit: BoxFit.cover);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 48, height: 48, child: child),
    );
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({
    this.existing,
    this.catalog = const [],
  });

  final PlatformProduct? existing;
  final List<PlatformProduct> catalog;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _price;
  late final TextEditingController _unit;
  late final TextEditingController _stock;
  late final TextEditingController _sort;
  late bool _active;
  late bool _featured;
  late bool _inMarket;
  late String _goodsKind;
  late String _docId;
  late List<String> _imageUrls;
  bool _uploading = false;
  StreamSubscription<html.Event>? _pasteSub;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _docId = (e?.id.isNotEmpty == true)
        ? e!.id
        : FirebaseFirestore.instance.collection('platform_products').doc().id;
    _name = TextEditingController(text: e?.name ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _price = TextEditingController(text: e != null ? '${e.price}' : '');
    _unit = TextEditingController(text: e?.unit ?? 'дона');
    _stock = TextEditingController(
      text: e != null ? '${e.totalStock}' : '0',
    );
    _sort = TextEditingController(text: e != null ? '${e.sortOrder}' : '0');
    _active = e?.active ?? true;
    _featured = e?.featuredOnHome ?? false;
    _inMarket = e?.showInMarket ?? true;
    _goodsKind = e?.goodsKind ?? '';
    _imageUrls = List<String>.from(e?.displayImages ?? const <String>[]);
    _pasteSub = html.document.onPaste.listen(_onDocumentPaste);
  }

  @override
  void dispose() {
    _pasteSub?.cancel();
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    _unit.dispose();
    _stock.dispose();
    _sort.dispose();
    super.dispose();
  }

  void _onDocumentPaste(html.Event event) {
    if (_uploading || !mounted) return;
    final e = event as html.ClipboardEvent;
    if (!ClipboardPasteImage.looksLikeImagePaste(e)) return;
    e.preventDefault();
    e.stopPropagation();
    unawaited(_handlePasteEvent(e));
  }

  Future<void> _handlePasteEvent(html.ClipboardEvent e) async {
    try {
      final pasted = await ClipboardPasteImage.fromPasteEvent(e);
      if (pasted == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text(
                'Нусхадаги расм ўқилмади. ChatGPT’да «Copy image» ёки «Save image» → «Расм танлаш».',
              ),
            ),
          );
        }
        return;
      }
      await _uploadBytes(pasted.bytes, pasted.mime);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Нусхадан ўқиш хато: $err'),
          ),
        );
      }
    }
  }

  Future<void> _uploadBytes(Uint8List bytes, String mime) async {
    if (_uploading) return;
    if (_imageUrls.length >= PlatformProduct.maxImages) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Энг кўпи 5 та расм'),
          ),
        );
      }
      return;
    }
    setState(() => _uploading = true);
    try {
      final prepared = await WebImageCompress.prepareForUpload(
        bytes,
        mimeHint: mime,
      );
      final url = await BreadImageStorage().uploadPlatformImage(
        docId: _docId,
        bytes: prepared.bytes,
        contentType: prepared.mime,
        index: _imageUrls.length,
      );
      if (!mounted) return;
      setState(() => _imageUrls = [..._imageUrls, url]);
      final note = prepared.bytes.length < bytes.length
          ? 'Расм юкланди (сиқилди)'
          : 'Расм юкланди';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.button,
          content: Text(note),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(e is StateError ? e.message : 'Расм: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickImage() async {
    if (_uploading) return;
    final room = PlatformProduct.maxImages - _imageUrls.length;
    if (room <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Энг кўпи 5 та расм'),
        ),
      );
      return;
    }
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final files = res.files.take(room).toList();
      for (final f in files) {
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.orange,
                content: Text('Файл ўқилмади — кичикроқ JPG/PNG танланг.'),
              ),
            );
          }
          continue;
        }
        final name = f.name.toLowerCase();
        final mime = name.endsWith('.png')
            ? 'image/png'
            : name.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg';
        await _uploadBytes(bytes, mime);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Расм: $e')),
        );
      }
    }
  }

  void _removeImageAt(int i) {
    if (i < 0 || i >= _imageUrls.length) return;
    setState(() {
      _imageUrls = [..._imageUrls]..removeAt(i);
    });
  }

  int _dupNameCount() {
    final n = _name.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return 0;
    final exceptId = widget.existing?.id;
    return widget.catalog.where((p) {
      if (exceptId != null && p.id == exceptId) return false;
      final pn = p.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      return pn == n;
    }).length;
  }

  void _save() {
    final name = _name.text.trim();
    final price = int.tryParse(_price.text.trim()) ?? -1;
    if (name.isEmpty || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ном ва нарх мажбурий')),
      );
      return;
    }
    final existing = widget.existing;
    final urls = _imageUrls
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(PlatformProduct.maxImages)
        .toList(growable: false);
    Navigator.pop(
      context,
      PlatformProduct(
        id: existing?.id.isNotEmpty == true ? existing!.id : _docId,
        name: name,
        description: _desc.text.trim(),
        price: price,
        imageUrl: urls.isEmpty ? '' : urls.first,
        imageUrls: urls,
        unit: _unit.text.trim().isEmpty ? 'дона' : _unit.text.trim(),
        minQty: existing?.minQty ?? 1,
        step: existing?.step ?? 1,
        totalStock: int.tryParse(_stock.text.trim()) ?? 0,
        soldToday: existing?.soldToday ?? 0,
        active: _active,
        featuredOnHome: _featured,
        showInMarket: _inMarket,
        sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
        goodsKind: _goodsKind,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _imageUrls.length;
    final canAdd = count < PlatformProduct.maxImages;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Янги маҳсулот' : 'Таҳрир'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _imageUrls.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 96,
                                height: 96,
                                child: isHttpImageUrl(_imageUrls[i])
                                    ? CachedNetworkImage(
                                        imageUrl: _imageUrls[i],
                                        fit: BoxFit.cover,
                                      )
                                    : const ColoredBox(
                                        color: Color(0xFFEAF6EB),
                                        child: Icon(Icons.image_outlined),
                                      ),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Material(
                                color: Colors.black54,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _uploading
                                      ? null
                                      : () => _removeImageAt(i),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
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
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.button,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Асосий',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (canAdd)
                      OutlinedButton(
                        onPressed: _uploading ? null : _pickImage,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(96, 96),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _uploading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate),
                                  SizedBox(height: 4),
                                  Text('Қўшиш', style: TextStyle(fontSize: 11)),
                                ],
                              ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_uploading || !canAdd) ? null : _pickImage,
                      icon: const Icon(Icons.add_photo_alternate),
                      label: Text(
                        _uploading
                            ? 'Юкланмоқда...'
                            : 'Расм танлаш ($count/${PlatformProduct.maxImages})',
                      ),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  '1–5 та расм. Файл ёки Ctrl+V. Катта расм авто сиқилади.',
                  style: TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
              ),
              TextField(
                controller: _name,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Ном',
                  errorText: _dupNameCount() > 0
                      ? 'Диққат: шу номли ${_dupNameCount()} та маҳсулот бор'
                      : null,
                ),
              ),
              TextField(
                controller: _desc,
                decoration: const InputDecoration(labelText: 'Тавсиф'),
                maxLines: 2,
              ),
              TextField(
                controller: _price,
                decoration: const InputDecoration(labelText: 'Нарх (сўм)'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              TextField(
                controller: _unit,
                decoration: const InputDecoration(labelText: 'Бирлик'),
              ),
              TextField(
                controller: _stock,
                decoration: const InputDecoration(
                  labelText: 'Омбор (0 = лимитсиз)',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              TextField(
                controller: _sort,
                enabled: widget.existing != null,
                decoration: InputDecoration(
                  labelText: widget.existing == null
                      ? 'Тартиб (авто: рўйхат охири)'
                      : 'Тартиб',
                  helperText: widget.existing == null
                      ? 'Янги маҳсулот жойлаштириш вақти бўйича охирига қўшилади'
                      : null,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 8),
              Text(
                'Категория',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: PlatformProduct.kindFood,
                    label: Text('Озиқ'),
                    icon: Icon(Icons.restaurant_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: PlatformProduct.kindNonFood,
                    label: Text('Но-озиқ'),
                    icon: Icon(Icons.shopping_bag_outlined, size: 16),
                  ),
                ],
                emptySelectionAllowed: true,
                selected: _goodsKind.isEmpty ? <String>{} : {_goodsKind},
                onSelectionChanged: (s) {
                  setState(() => _goodsKind = s.isEmpty ? '' : s.first);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Фаол'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Тавсия этамиз (витрина)'),
                subtitle: const Text('ҚЎЛДА режимда витринага чиқади'),
                value: _featured,
                onChanged: (v) => setState(() => _featured = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Онлайн бозорда кўрсатиш'),
                value: _inMarket,
                onChanged: (v) => setState(() => _inMarket = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.pop(context),
          child: const Text('Бекор'),
        ),
        FilledButton(
          onPressed: _uploading ? null : _save,
          child: const Text('Сақлаш'),
        ),
      ],
    );
  }
}

class _BulkImageSeed {
  const _BulkImageSeed({
    required this.bytes,
    required this.mime,
    required this.name,
  });

  final Uint8List bytes;
  final String mime;
  final String name;
}

class _BulkRow {
  _BulkRow({
    required this.bytes,
    required this.mime,
    required String name,
  }) : nameCtrl = TextEditingController(text: name),
       priceCtrl = TextEditingController();

  final Uint8List bytes;
  final String mime;
  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;
  String goodsKind = '';

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
  }
}

/// Бирданига кўп маҳсулот: ҳар расм = битта товар.
class _BulkAddDialog extends StatefulWidget {
  const _BulkAddDialog({
    required this.seeds,
    required this.repo,
  });

  final List<_BulkImageSeed> seeds;
  final PlatformProductsRepository repo;

  @override
  State<_BulkAddDialog> createState() => _BulkAddDialogState();
}

class _BulkAddDialogState extends State<_BulkAddDialog> {
  late final List<_BulkRow> _rows;
  late String _defaultKind;
  bool _saving = false;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _defaultKind = '';
    _rows = widget.seeds
        .map(
          (s) => _BulkRow(bytes: s.bytes, mime: s.mime, name: s.name),
        )
        .toList();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _applyKindToAll(String kind) {
    setState(() {
      _defaultKind = kind;
      for (final r in _rows) {
        r.goodsKind = kind;
      }
    });
  }

  /// Бир қатор Но-озиқ → қолган қаторлар Озиқ.
  void _setRowKind(int index, String kind) {
    setState(() {
      _rows[index].goodsKind = kind;
      if (kind == PlatformProduct.kindNonFood) {
        for (var i = 0; i < _rows.length; i++) {
          if (i == index) continue;
          if (_rows[i].goodsKind != PlatformProduct.kindNonFood) {
            _rows[i].goodsKind = PlatformProduct.kindFood;
          }
        }
        _defaultKind = '';
      }
    });
  }

  void _removeAt(int i) {
    if (_saving || _rows.length <= 1) return;
    setState(() {
      _rows.removeAt(i).dispose();
    });
  }

  Future<void> _saveAll() async {
    if (_saving) return;
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final name = r.nameCtrl.text.trim();
      final price = int.tryParse(r.priceCtrl.text.trim()) ?? -1;
      if (name.isEmpty || price < 0) {
        setState(() {
          _error = 'Қатор ${i + 1}: ном ва нарх мажбурий';
        });
        return;
      }
    }
    setState(() {
      _saving = true;
      _progress = 0;
      _error = null;
    });

    final storage = BreadImageStorage();
    var ok = 0;
    try {
      var nextOrder = await widget.repo.nextSortOrder();
      for (var i = 0; i < _rows.length; i++) {
        if (!mounted) return;
        setState(() => _progress = i + 1);
        final r = _rows[i];
        final docId =
            FirebaseFirestore.instance.collection('platform_products').doc().id;
        final prepared = await WebImageCompress.prepareForUpload(
          r.bytes,
          mimeHint: r.mime,
        );
        final url = await storage.uploadPlatformImage(
          docId: docId,
          bytes: prepared.bytes,
          contentType: prepared.mime,
          index: 0,
        );
        final product = PlatformProduct(
          id: docId,
          name: r.nameCtrl.text.trim(),
          price: int.parse(r.priceCtrl.text.trim()),
          imageUrl: url,
          imageUrls: [url],
          unit: 'дона',
          active: true,
          featuredOnHome: false,
          showInMarket: true,
          sortOrder: nextOrder,
          goodsKind: r.goodsKind.isEmpty
              ? PlatformProduct.kindFood
              : r.goodsKind,
        );
        // create() ҳам nextSortOrder қилади — бажаришдан олдин force қиламиз.
        await widget.repo.createAppended(product, sortOrder: nextOrder);
        nextOrder++;
        ok++;
      }
      if (!mounted) return;
      Navigator.pop(context, ok);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = ok > 0
            ? '$ok та сақланди, кейин хато: $e'
            : 'Хато: $e';
      });
    }
  }

  void _previewImage(Uint8List bytes, String title) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: size.width,
            height: size.height * 0.9,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Center(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    color: Colors.black54,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title.isEmpty ? 'Расм' : title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Ёпиш',
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Text(
                    'Катталаштириш: сичқонча ғилдираги / pinch',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final dialogW = w >= 900 ? 720.0 : (w - 48).clamp(320.0, 720.0);
    return AlertDialog(
      title: Text('Кўп қўшиш (${_rows.length} та)'),
      content: SizedBox(
        width: dialogW,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ҳар бир расм — алоҳида маҳсулот. Ном ва нархни тўлдиринг.\n'
              'Но-озиқ белгиланса, қолганлари автомат Озиқ бўлади.',
              style: TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Ҳаммасига категория:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: PlatformProduct.kindFood,
                      label: Text('Озиқ'),
                    ),
                    ButtonSegment(
                      value: PlatformProduct.kindNonFood,
                      label: Text('Но-озиқ'),
                    ),
                  ],
                  emptySelectionAllowed: true,
                  selected:
                      _defaultKind.isEmpty ? <String>{} : {_defaultKind},
                  onSelectionChanged: _saving
                      ? null
                      : (s) => _applyKindToAll(s.isEmpty ? '' : s.first),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            if (_saving)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: _rows.isEmpty
                          ? null
                          : _progress / _rows.length,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Юкланмоқда: $_progress / ${_rows.length}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                    final r = _rows[i];
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Tooltip(
                              message: 'Катта кўриш',
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _saving
                                      ? null
                                      : () => _previewImage(
                                            r.bytes,
                                            r.nameCtrl.text.trim().isEmpty
                                                ? 'Расм ${i + 1}'
                                                : r.nameCtrl.text.trim(),
                                          ),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.memory(
                                          r.bytes,
                                          width: 64,
                                          height: 64,
                                          fit: BoxFit.cover,
                                          gaplessPlayback: true,
                                        ),
                                      ),
                                      Positioned(
                                        right: 2,
                                        bottom: 2,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Icon(
                                            Icons.zoom_in,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    controller: r.nameCtrl,
                                    enabled: !_saving,
                                    decoration: const InputDecoration(
                                      labelText: 'Ном',
                                      isDense: true,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: r.priceCtrl,
                                          enabled: !_saving,
                                          decoration: const InputDecoration(
                                            labelText: 'Нарх',
                                            isDense: true,
                                          ),
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SegmentedButton<String>(
                                        style: const ButtonStyle(
                                          visualDensity: VisualDensity.compact,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        segments: const [
                                          ButtonSegment(
                                            value: PlatformProduct.kindFood,
                                            label: Text('Озиқ'),
                                          ),
                                          ButtonSegment(
                                            value: PlatformProduct.kindNonFood,
                                            label: Text('Но'),
                                          ),
                                        ],
                                        emptySelectionAllowed: true,
                                        selected: r.goodsKind.isEmpty
                                            ? <String>{}
                                            : {r.goodsKind},
                                        onSelectionChanged: _saving
                                            ? null
                                            : (s) {
                                                _setRowKind(
                                                  i,
                                                  s.isEmpty ? '' : s.first,
                                                );
                                              },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (!_saving && _rows.length > 1)
                              IconButton(
                                tooltip: 'Ўчириш',
                                onPressed: () => _removeAt(i),
                                icon: const Icon(Icons.close, size: 20),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, 0),
          child: const Text('Бекор'),
        ),
        FilledButton(
          onPressed: _saving ? null : _saveAll,
          child: Text(
            _saving
                ? 'Сақланмоқда…'
                : 'Ҳаммасини сақлаш (${_rows.length})',
          ),
        ),
      ],
    );
  }
}
