import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../tv_market/models/tv_ad_prefill.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../tv_market/screens/tv_publish_screen.dart';
import '../domain/business.dart';
import 'business_product_form_screen.dart';

/// Эганинг объекти маҳсулотлари: рўйхат, қўшиш, таҳрирлаш, ўчириш (юмшоқ ўчириш — `status: deleted`).
/// Сони чекланмаган (эга қарори, 2026-10-24).
class BusinessProductsScreen extends StatefulWidget {
  const BusinessProductsScreen({super.key, required this.business, TvShopRepository? repository, this.onPromote})
      : _repo = repository;

  final Business business;
  final TvShopRepository? _repo;

  /// «Реклама қилиш» — тест учун алмаштирилади; бўлмаса пуллик реклама экрани (`TvPublishScreen`) очилади.
  final void Function(BuildContext context, TvShopItem item)? onPromote;

  @override
  State<BusinessProductsScreen> createState() => _BusinessProductsScreenState();
}

class _BusinessProductsScreenState extends State<BusinessProductsScreen> {
  late final TvShopRepository _repo = widget._repo ?? TvShopRepository();
  late Future<List<TvShopItem>> _future = _load();

  Future<List<TvShopItem>> _load() =>
      _repo.fetchByBusiness(widget.business.id, ownerPhone: widget.business.ownerId, onlyActive: false);

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _openForm([TvShopItem? item]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => BusinessProductFormScreen(business: widget.business, existing: item)),
    );
    if (changed == true && mounted) _reload();
  }

  /// Каталог маҳсулоти → пуллик АВАГрам рекламаси (алоҳида механизм): мавжуд реклама экрани ном/нарх/тавсиф
  /// олдиндан тўлдирилган ҳолда очилади; видео, тариф ва тўловни эга шу ерда танлайди.
  void _promote(TvShopItem item) {
    final custom = widget.onPromote;
    if (custom != null) return custom(context, item);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TvPublishScreen(hideShopOption: true, adPrefill: TvAdPrefill.fromItem(item)),
    ));
  }

  Future<void> _delete(TvShopItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('bizprod_delete_title')),
        content: Text(item.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('bizmap_delete'), style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.deleteItem(item.id);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('bizprod_deleted'))));
      _reload();
    } catch (e) {
      debugPrint('[BusinessProducts] delete: $e');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('bizprod_err_generic'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${context.tr('bizprod_title')} · ${widget.business.name}', maxLines: 1)),
      body: FutureBuilder<List<TvShopItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(context.tr('bizprod_err_generic')));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.primaryDark),
                    const SizedBox(height: 12),
                    Text(context.tr('bizprod_empty'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final it = items[i];
              final cover = it.coverPhotoUrl;
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: SizedBox(
                    width: 52,
                    height: 52,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: cover.isEmpty
                          ? const ColoredBox(color: Color(0x11000000), child: Icon(Icons.image_not_supported_outlined))
                          : Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                  title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      if (it.hasPrice) formatMoney(it.price),
                      context.tr(it.kind == 'service' ? 'bizprod_kind_service' : 'bizprod_kind_product'),
                      if (it.hasVideo) context.tr('bizprod_has_video'),
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _openForm(it),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (it.isActive)
                        IconButton(
                          key: ValueKey('bizprod_promote_${it.id}'),
                          tooltip: context.tr('bizprod_promote'),
                          icon: const Icon(Icons.campaign_outlined),
                          onPressed: () => _promote(it),
                        ),
                      IconButton(
                        tooltip: context.tr('bizmap_delete'),
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _delete(it),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('bizprod_fab'),
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: Text(context.tr('bizprod_add')),
      ),
    );
  }
}
