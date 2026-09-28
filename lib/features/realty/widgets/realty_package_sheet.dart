import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../realty_tabs.dart';

/// Ахборот пакети сотиб олиш варағи (концепция, 4-бўлим).
///
/// Муҳим фарқ: бу уй сотилгани учун комиссия ЭМАС. AVA объектлар
/// ҳақидаги ахборот хизмати учун ҳақ олади — пакет шунча объектнинг
/// аниқ маълумотини очиш ҳуқуқини беради. Ахборот пакети ва риэлторлик
/// хизмати иккита алоҳида маҳсулот.
///
/// `true` қайтарса — пакет олинди, чақирувчи амални давом эттириши мумкин.
Future<bool> showRealtyPackageSheet(BuildContext context) async {
  final bought = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PackageSheet(),
  );
  return bought == true;
}

class _PackageSheet extends StatefulWidget {
  const _PackageSheet();

  @override
  State<_PackageSheet> createState() => _PackageSheetState();
}

class _PackageSheetState extends State<_PackageSheet> {
  final _repo = RealtyRepository();

  Map<int, int> _pricing = const {};
  bool _loading = true;
  bool _busy = false;
  int? _size;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pricing = await _repo.loadPackagePricing();
    if (!mounted) return;
    setState(() {
      _pricing = pricing;
      _loading = false;
      if (pricing.isNotEmpty) {
        _size = (pricing.keys.toList()..sort()).first;
      }
    });
  }

  Future<void> _buy() async {
    final size = _size;
    if (size == null || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final left = await _repo.purchasePackage(size);
      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text(
          '${context.tr('realty_package_bought')} · '
          '${context.tr('realty_unlocks_left')}: $left',
        ),
        backgroundColor: RealtyTabs.colorFor(RealtyTier.plain),
        behavior: SnackBarBehavior.floating,
      ));
    } on RealtyException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(
        content: Text(
          e.code == 'insufficient_balance'
              ? context.tr('realty_error_balance')
              : context.tr('realty_error_generic'),
        ),
        backgroundColor: RealtyTabs.colorFor(RealtyTier.urgent),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final price = _size == null ? null : _pricing[_size];
    final sizes = _pricing.keys.toList()..sort();
    return SafeArea(
      top: false,
      child: Material(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('realty_package_title'),
                style: TextStyle(
                  fontSize: AppText.titleMedium,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('realty_package_body'),
                style: TextStyle(fontSize: AppText.bodySmall, color: c.ink2),
              ),
              const SizedBox(height: 16),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Row(
                  children: [
                    for (final s in sizes) ...[
                      Expanded(
                        child: GestureDetector(
                          onTap: _busy ? null : () => setState(() => _size = s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _size == s ? c.brand : c.bg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _size == s ? c.brand : c.line,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '$s',
                                  style: TextStyle(
                                    fontSize: AppText.titleLarge,
                                    fontWeight: FontWeight.w800,
                                    color: _size == s ? c.brandInk : c.ink,
                                  ),
                                ),
                                Text(
                                  context.tr('realty_package_objects'),
                                  style: TextStyle(
                                    fontSize: AppText.labelTiny,
                                    color: _size == s ? c.brandInk : c.ink3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formatPrice(_pricing[s] ?? 0),
                                  style: TextStyle(
                                    fontSize: AppText.bodySmall,
                                    fontWeight: FontWeight.w700,
                                    color: _size == s ? c.brandInk : c.ink2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ],
                ),
              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: (_busy || _loading || price == null) ? null : _buy,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: c.brandInk,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        price == null
                            ? context.tr('realty_price_unavailable')
                            : '${context.tr('realty_package_buy')} · '
                                '${formatMoney(price)}',
                        style: const TextStyle(
                          fontSize: AppText.bodyLarge,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('realty_package_hint'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
