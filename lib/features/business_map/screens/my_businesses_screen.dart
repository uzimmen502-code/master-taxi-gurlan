import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../data/business_repository.dart';
import '../domain/business.dart';
import 'business_form_screen.dart';
import 'business_products_screen.dart';

/// Эганинг ўз объектлари: рўйхат, қўшиш, таҳрирлаш, ўчириш (B-1, B-8).
class MyBusinessesScreen extends StatefulWidget {
  const MyBusinessesScreen({super.key, BusinessRepository? repository, this.ownerId})
      : _repo = repository;

  final BusinessRepository? _repo;

  /// Тест учун; бўлмаса — жорий фойдаланувчи телефони.
  final String? ownerId;

  @override
  State<MyBusinessesScreen> createState() => _MyBusinessesScreenState();
}

class _MyBusinessesScreenState extends State<MyBusinessesScreen> {
  late final BusinessRepository _repo = widget._repo ?? BusinessRepository();
  late final String _uid =
      widget.ownerId ?? canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
  late final Stream<List<Business>> _stream = _repo.watchMine(_uid);

  Future<void> _openForm([Business? b]) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BusinessFormScreen(existing: b)));

  Future<void> _openProducts(Business b) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BusinessProductsScreen(business: b)));

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
            child: Text(context.tr('bizmap_delete'), style: TextStyle(color: Colors.red.shade700)),
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
      BusinessRepository.errorCode(e);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(context.tr('bizmap_err_generic'))));
    }
  }

  @override
  Widget build(BuildContext context) {
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
