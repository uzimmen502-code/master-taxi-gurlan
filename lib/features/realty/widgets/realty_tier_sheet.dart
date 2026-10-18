import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/idempotency_keys.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../realty_tabs.dart';
import 'realty_controls.dart';
import 'realty_feedback.dart';
import 'realty_wallet.dart';
import '../../../shared/widgets/wallet_topup_ui.dart';

/// РЕКЛАМА / СРОЧНО сотиб олиш ва узайтириш варағи.
///
/// Нархлар сервердан келади (`settings/app.realtyPricing`, админ
/// панелдан таҳрирланади) — иловада қатъий нарх ёзилмайди, шунда тариф
/// ўзгарса релиз кутилмайди.
///
/// Тўлов AVA ҳамёнидан. Баланс етмаса «Ҳамённи тўлдиринг» дейилади ва
/// сотиб олиш амалга ошмайди.
///
/// [bulkCount] берилса — гуруҳли режим: варақ [listing] га сотиб олади
/// ва танланган даража/муддатни қайтаради, чақирувчи уни қолган
/// объектларга қўллайди (концепция, 5-бўлим: «гуруҳли амаллар»).
Future<RealtyTierChoice?> showRealtyTierSheet(
  BuildContext context, {
  required RealtyListing listing,
  int bulkCount = 1,
  RealtyRepository? repository,
  Stream<int>? balance,
  VoidCallback? openWallet,
}) {
  return showModalBottomSheet<RealtyTierChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TierSheet(
      listing: listing,
      bulkCount: bulkCount,
      repository: repository,
      balance: balance,
      openWallet: openWallet,
    ),
  );
}

/// Варақда танланган даража ва муддат.
class RealtyTierChoice {
  const RealtyTierChoice({required this.tier, required this.durationDays});

  final RealtyTier tier;
  final int durationDays;
}

class _TierSheet extends StatefulWidget {
  const _TierSheet({
    required this.listing,
    this.bulkCount = 1,
    this.repository,
    this.balance,
    this.openWallet,
  });

  final RealtyListing listing;
  final int bulkCount;
  final RealtyRepository? repository;
  final Stream<int>? balance;
  final VoidCallback? openWallet;

  @override
  State<_TierSheet> createState() => _TierSheetState();
}

class _TierSheetState extends State<_TierSheet> {
  late final RealtyRepository _repo = widget.repository ?? RealtyRepository();
  final _keys = IdempotencyKeys();

  /// Эганинг баланси — етмаслигини сотиб олишдан ОЛДИН кўрсатиш учун.
  late final Stream<int> _balance = widget.balance ?? walletBalanceStream();

  Map<RealtyTier, Map<int, int>> _pricing = const {};
  bool _loading = true;
  bool _busy = false;

  /// Харид хатоси — варақнинг ИЧИДА (snackbar варақ ортида қолади).
  String? _error;
  bool _errorTopUp = false;

  late RealtyTier _tier = widget.listing.tier.isPaid
      ? widget.listing.tier
      : RealtyTier.promo;
  int? _days;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pricing = await _repo.loadPricing();
    if (!mounted) return;
    setState(() {
      _pricing = pricing;
      _loading = false;
      _days ??= _tier.durationOptions.first;
    });
  }

  int? get _price => _pricing[_tier]?[_days];

  /// Ҳозирги даража ҳали амал қилаётган бўлса — «узайтириш».
  bool get _isRenew =>
      widget.listing.tier == _tier &&
      (widget.listing.tierUntil?.isAfter(DateTime.now()) ?? false);

  Future<void> _buy() async {
    final days = _days;
    if (days == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Ният: шу эълон + даража + муддат. Калит шу ният тугагунча ўзгармайди:
    // жавоб йўқолса қайта уриниш пулни иккинчи марта ЕЧМАЙДИ.
    final scope = 'tier:${widget.listing.id}:${_tier.key}:$days';
    try {
      final res = await _repo.purchaseTier(
        listingId: widget.listing.id,
        tier: _tier,
        durationDays: days,
        idempotencyKey: _keys.keyFor(scope),
      );
      _keys.settled(scope);
      if (!mounted) return;
      navigator.pop(RealtyTierChoice(tier: _tier, durationDays: days));
      showRealtyInfo(
        messenger,
        // `formatMoney` ўзи «сўм» қўшади — такрорламаймиз.
        '${context.tr('realty_tier_bought')} · ${formatMoney(res.price)}',
        background: RealtyTabs.colorFor(_tier),
      );
    } on RealtyException catch (e) {
      // Сервер АНИҚ рад этди — пул ечилмаган.
      _keys.settled(scope);
      if (!mounted) return;
      // Хато варақнинг ИЧИДА: snackbar варақ очиқ турганда унинг ортида қолади.
      setState(() {
        _busy = false;
        _error = realtyErrorText(context, e);
        _errorTopUp = realtyNeedsTopUp(e);
      });
    } catch (_) {
      // Натижа НОМАЪЛУМ (тармоқ узилди): калит сақланади, тугма қотиб қолмайди.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.tr('realty_error_generic');
        _errorTopUp = false;
      });
    }
  }

  void _openWallet() =>
      (widget.openWallet ?? () => openWalletTopUp(Navigator.of(context)))();

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final price = _price;
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
                context.tr('realty_tier_sheet_title'),
                style: TextStyle(
                  fontSize: AppText.titleMedium,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.bulkCount > 1
                    ? '${context.tr('realty_bulk_selected')}: '
                        '${widget.bulkCount}'
                    : widget.listing.titleOrText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppText.bodySmall, color: c.ink3),
              ),
              if (widget.bulkCount > 1) ...[
                const SizedBox(height: 4),
                Text(
                  context.tr('realty_bulk_price_hint'),
                  style: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
                ),
              ],
              const SizedBox(height: 16),

              Row(
                children: [
                  for (final tier in const [
                    RealtyTier.promo,
                    RealtyTier.urgent,
                  ]) ...[
                    Expanded(
                      child: RealtyChoice(
                        label: context.tr(RealtyTabs.labelKey(tier)),
                        selected: _tier == tier,
                        color: RealtyTabs.colorFor(tier),
                        onTap: _busy
                            ? null
                            : () => setState(() {
                                  _tier = tier;
                                  _days = tier.durationOptions.first;
                                  _error = null;
                                }),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              Text(
                context.tr('realty_tier_duration'),
                style: TextStyle(
                  fontSize: AppText.labelLarge,
                  fontWeight: FontWeight.w700,
                  color: c.ink2,
                ),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Row(
                  children: [
                    for (final d in _tier.durationOptions) ...[
                      Expanded(
                        child: RealtyChoice(
                          label: '$d ${context.tr('realty_days_short')}',
                          // Тор катакча — «сўм»сиз, фақат рақам.
                          sub: _pricing[_tier]?[d] == null
                              ? '—'
                              : formatPrice(_pricing[_tier]![d]!),
                          selected: _days == d,
                          color: RealtyTabs.colorFor(_tier),
                          onTap: _busy
                              ? null
                              : () => setState(() {
                                    _days = d;
                                    _error = null;
                                  }),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              const SizedBox(height: 16),

              // Баланс етмаса — сотиб олишдан олдин огоҳлантириш ва «Ҳамённи тўлдириш».
              WalletBalanceNotice(
                balance: _balance,
                price: price,
                onTopUp: _openWallet,
              ),
              if (_error != null)
                WalletInlineError(text: _error!, onTopUp: _errorTopUp ? _openWallet : null),

              ElevatedButton(
                onPressed: (_busy || _loading || price == null) ? null : _buy,
                style: ElevatedButton.styleFrom(
                  backgroundColor: RealtyTabs.colorFor(_tier),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        price == null
                            ? context.tr('realty_price_unavailable')
                            : '${context.tr(_isRenew ? 'realty_tier_renew' : 'realty_tier_buy')}'
                                ' · ${formatMoney(price)}',
                        style: const TextStyle(
                          fontSize: AppText.bodyLarge,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('realty_tier_wallet_hint'),
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

