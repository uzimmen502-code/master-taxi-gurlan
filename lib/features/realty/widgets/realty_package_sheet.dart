import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/idempotency_keys.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../realty_tabs.dart';
import 'realty_feedback.dart';
import 'realty_wallet.dart';

/// Ахборот пакети сотиб олиш варағи (концепция, 4-бўлим).
///
/// Муҳим фарқ: бу уй сотилгани учун комиссия ЭМАС. AVA объектлар
/// ҳақидаги ахборот хизмати учун ҳақ олади — пакет шунча объектнинг
/// аниқ маълумотини очиш ҳуқуқини беради. Ахборот пакети ва риэлторлик
/// хизмати иккита алоҳида маҳсулот.
///
/// `true` қайтарса — пакет олинди, чақирувчи амални давом эттириши мумкин.
///
/// [repository], [balance], [openWallet] — тест учун алмаштириладиганлар.
Future<bool> showRealtyPackageSheet(
  BuildContext context, {
  RealtyRepository? repository,
  Stream<int>? balance,
  VoidCallback? openWallet,
}) async {
  final bought = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PackageSheet(repository: repository, balance: balance, openWallet: openWallet),
  );
  return bought == true;
}

class _PackageSheet extends StatefulWidget {
  const _PackageSheet({this.repository, this.balance, this.openWallet});

  final RealtyRepository? repository;
  final Stream<int>? balance;
  final VoidCallback? openWallet;

  @override
  State<_PackageSheet> createState() => _PackageSheetState();
}

class _PackageSheetState extends State<_PackageSheet> {
  late final RealtyRepository _repo = widget.repository ?? RealtyRepository();

  /// Эганинг баланси — етмаслигини сотиб олишдан ОЛДИН кўрсатиш учун.
  late final Stream<int> _balance = widget.balance ?? realtyBalanceStream();

  /// Ҳар ўлчам — ўз ИДЕМПОТЕНТЛИК калити: жавоб йўқолиб (таймаут) қайта
  /// босилса, сервер пулни иккинчи марта ЕЧМАЙДИ. Аввал калит ҳар
  /// босишда янги эди — пул ечилган бўлса ҳам қайта босиш яна ечарди.
  final _keys = IdempotencyKeys();

  Map<int, int> _pricing = const {};
  bool _loading = true;
  bool _busy = false;
  int? _size;

  /// Харид хатоси — варақнинг ИЧИДА (snackbar варақ ортида қолади).
  String? _error;
  bool _errorTopUp = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final pricing = await _repo.loadPackagePricing();
    if (!mounted) return;
    setState(() {
      _pricing = pricing;
      _loading = false;
      if (pricing.isNotEmpty && !pricing.containsKey(_size)) {
        _size = (pricing.keys.toList()..sort()).first;
      }
    });
  }

  Future<void> _buy() async {
    final size = _size;
    if (size == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final scope = 'pkg:$size';
    try {
      final left = await _repo.purchasePackage(size, idempotencyKey: _keys.keyFor(scope));
      _keys.settled(scope);
      if (!mounted) return;
      navigator.pop(true);
      showRealtyInfo(
        messenger,
        '${context.tr('realty_package_bought')} · '
        '${context.tr('realty_unlocks_left')}: $left',
        background: RealtyTabs.colorFor(RealtyTier.plain),
      );
    } on RealtyException catch (e) {
      // Сервер АНИҚ рад этди (масалан, баланс етмайди) — пул ечилмаган.
      _keys.settled(scope);
      if (!mounted) return;
      // Хато варақнинг ИЧИДА: snackbar варақ очиқ турганда унинг ортида
      // қолади (кўринмайди ва босилмайди).
      setState(() {
        _busy = false;
        _error = realtyErrorText(context, e);
        _errorTopUp = RealtyInlineError.needsTopUp(e);
      });
    } catch (_) {
      // Тармоқ узилиши ва бошқа кутилмаган хато — НАТИЖА НОМАЪЛУМ: калит
      // сақланади (қайта уриниш пулни яна емайди). Аввал бу шохда
      // `_busy` ўчмасди — тугма абадий айланиб қолар эди.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.tr('realty_error_generic');
        _errorTopUp = false;
      });
    }
  }

  void _openWallet() =>
      (widget.openWallet ?? () => openRealtyWallet(Navigator.of(context)))();

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
                          onTap: _busy ? null : () => setState(() {
                                _size = s;
                                _error = null;
                              }),
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
              // Нарх юкланмаган бўлса — қайта юклаш тугмаси (аввал варақни
              // ёпиб қайта очишдан бошқа йўл йўқ эди).
              if (!_loading && sizes.isEmpty)
                Center(
                  child: TextButton(
                    key: const ValueKey('realty-pricing-retry'),
                    onPressed: _load,
                    child: Text(context.tr('realty_pricing_retry')),
                  ),
                ),
              const SizedBox(height: 16),

              // Баланс: етмаса — огоҳлантириш ва «Ҳамённи тўлдириш» (тугма
              // ўчирилмайди: баланс эскирган бўлиши мумкин, ҳал қилувчи — сервер).
              RealtyBalanceNotice(
                balance: _balance,
                price: price,
                onTopUp: _openWallet,
              ),
              if (_error != null)
                RealtyInlineError(text: _error!, onTopUp: _errorTopUp ? _openWallet : null),

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
