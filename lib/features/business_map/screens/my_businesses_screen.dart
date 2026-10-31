import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/celebration_dialog.dart';
import '../../my_shop/shop_opened_celebration.dart';
import '../data/business_repository.dart';
import '../domain/business.dart';
import '../domain/product_kind.dart' as product_kind;
import 'business_form_screen.dart';
import 'business_products_screen.dart';

/// Янги объект эганинг рўйхатига (Firestore обунаси) тушгунча кутади: аввал [current], бўлмаса [watch] ([timeout]).
/// Топилмаса — `null`: ҳеч нарса очилмайди, объект рўйхатда кўринади (эга қўлда очади).
/// «Менинг бизнесим» ва «Менинг дўконим» (MyShopScreen) учун ягона мантиқ.
Future<Business?> waitForMyBusiness(
  String id, {
  required List<Business> current,
  Stream<List<Business>>? watch,
  Duration timeout = const Duration(seconds: 8),
}) async {
  for (final b in current) {
    if (b.id == id) return b;
  }
  if (watch == null) return null;
  try {
    final list = await watch.firstWhere((l) => l.any((b) => b.id == id)).timeout(timeout);
    return list.firstWhere((b) => b.id == id);
  } catch (e) {
    debugPrint('[MyBusinesses] new business $id not visible yet: $e');
    return null;
  }
}

/// Эганинг ўз объектлари: рўйхат, қўшиш, таҳрирлаш, ўчириш (B-1, B-8).
class MyBusinessesScreen extends StatefulWidget {
  const MyBusinessesScreen({
    super.key,
    BusinessRepository? repository,
    this.ownerId,
    @visibleForTesting this.openForm,
    @visibleForTesting this.productsScreen,
  }) : _repo = repository;

  final BusinessRepository? _repo;

  /// Эга телефони (`canonicalPhoneId`). Берилмаса — жорий фойдаланувчи телефони.
  /// 9 рақамдан кам бўлса — сўров юборилмайди, «профилда телефон киритинг» ҳолати.
  final String? ownerId;

  /// Тест учун: объект формаси ўрнига (натижа — [BusinessFormScreen] каби: янги объект ID'си ёки `true`).
  final Future<Object?> Function(BuildContext context, Business? existing)? openForm;

  /// Тест учун: маҳсулотлар экрани ўрнига.
  final Widget Function(Business business)? productsScreen;

  @override
  State<MyBusinessesScreen> createState() => _MyBusinessesScreenState();
}

class _MyBusinessesScreenState extends State<MyBusinessesScreen> {
  late final BusinessRepository _repo = widget._repo ?? BusinessRepository();
  late final String _uid =
      widget.ownerId ?? canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
  // Телефонсиз `ownerId == ''` сўрови юборилмайди (обуна фақат телефон бўлса яратилади).
  late final bool _hasPhone = phoneDigits(_uid).length >= 9;
  late final Stream<List<Business>> _stream = _repo.watchMine(_uid);

  /// Ҳозирги рўйхат — янги объектни кутишда аввал шу ердан қидирилади.
  List<Business> _mine = const [];

  Future<void> _openForm([Business? b]) async {
    final result = await (widget.openForm?.call(context, b) ??
        Navigator.of(context).push<Object?>(
          MaterialPageRoute(builder: (_) => BusinessFormScreen(existing: b)),
        ));
    // Янги объект (филиал эмас) сақланди — маҳсулот сотадиган тур (чакана/улгуржи) бўлса, маҳсулотлар экрани
    // дарров очилади («Менинг дўконим» каби). Бошқа турлар (кафе, хизмат …) — рўйхатда қолади.
    // Таҳрир, филиал (`true`), бекор ёки хато — бу ерга келмайди.
    if (b != null || result is! String || result.isEmpty || !mounted) return;
    final created = await waitForMyBusiness(result, current: _mine, watch: _repo.watchMine(_uid));
    if (created == null || !mounted) return;
    // Табрик (эга, 2026-10-31) — шу объект учун бир марта: дўкон — «Дўконингиз очилди!» (кейин маҳсулотлар),
    // бошқа тур — «Бизнесингиз харитада!». Харитада кўринмайдиган (онлайн) бошқа тур — табриксиз.
    if (!product_kind.isShopCategory(created.category)) {
      if (!created.online) await _celebrateOnMapOnce(created.id);
      return;
    }
    await celebrateShopOpenedOnce(context, created.id);
    if (mounted) await _openProducts(created);
  }

  Future<void> _celebrateOnMapOnce(String id) async {
    if (!await CelebrationOnce.claim('business_on_map_$id') || !mounted) return;
    await showCelebration(
      context,
      icon: Icons.add_business_rounded,
      title: context.tr('bizmap_on_map_title'),
      subtitle: context.tr('bizmap_on_map_sub'),
      buttonLabel: context.tr('my_shop_continue'),
    );
  }

  Future<void> _openProducts(Business b) => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => widget.productsScreen?.call(b) ?? BusinessProductsScreen(business: b)),
      );

  Future<void> _delete(Business b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('bizmap_delete_title')),
        content: Text(b.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('bizmap_delete'), style: TextStyle(color: context.ava.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.deleteMine(b.id);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(context.tr('bizmap_deleted'))));
    } catch (e) {
      // `deleteMyBusiness`: блокланган объект — `BUSINESS_BLOCKED`; қолгани — умумий хабар (хом хато йўқ).
      final code = BusinessRepository.errorCode(e);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(context.tr(code == 'BUSINESS_BLOCKED' ? 'bizmap_delete_blocked' : 'bizmap_err_generic')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPhone) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('bizmap_my_title'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              context.tr('need_phone_profile'),
              key: const ValueKey('my_biz_need_phone'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('bizmap_my_title'))),
      body: StreamBuilder<List<Business>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(context.tr('bizmap_err_generic')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          _mine = list;
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_business_rounded, size: 56, color: AppColors.primaryDark),
                    const SizedBox(height: 12),
                    Text(
                      context.tr('bizmap_my_empty'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    // Бўш ҳолатда асосий ҳаракат кўзга ташлансин — FAB билан бир хил.
                    FilledButton.icon(
                      key: const ValueKey('my_biz_empty_add'),
                      onPressed: () => _openForm(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: AppColors.onPrimary,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.tr('bizmap_add_mine')),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final b = list[i];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(b.category.icon, color: AppColors.primaryDark),
                  title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [context.tr(b.category.labelKey), if (b.address.isNotEmpty) b.address].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _openForm(b),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: context.tr('bizprod_open'),
                        icon: const Icon(Icons.inventory_2_outlined),
                        onPressed: () => _openProducts(b),
                      ),
                      IconButton(
                        tooltip: context.tr('bizmap_delete'),
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _delete(b),
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
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: Text(context.tr('bizmap_add_mine')),
      ),
    );
  }
}
