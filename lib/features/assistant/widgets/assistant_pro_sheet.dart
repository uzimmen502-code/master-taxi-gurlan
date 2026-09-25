import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../models/assistant_status.dart';
import '../services/assistant_service.dart';

/// Pro пакетлар (7/15/30 кун) — ҳамёндан сотиб олиш.
///
/// `Navigator.pop(context, AssistantPurchaseResult)` — муваффақиятли харид.
class AssistantProSheet extends StatefulWidget {
  const AssistantProSheet({
    super.key,
    required this.status,
    required this.service,
    required this.onTopUp,
    this.limitReached = false,
  });

  final AssistantStatus status;
  final AssistantService service;
  final VoidCallback onTopUp;
  final bool limitReached;

  @override
  State<AssistantProSheet> createState() => _AssistantProSheetState();
}

class _AssistantProSheetState extends State<AssistantProSheet> {
  late int _balance = widget.status.balance;
  String? _buyingId;

  Future<void> _buy(AssistantPackage pkg) async {
    if (_buyingId != null) return;
    if (_balance < pkg.price) {
      _showInsufficient();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('assistant_pro_sheet_title')),
        content: Text(pkg.oneTime
            ? ctx.trMsg('assistant_buy_confirm_once',
                params: {'price': formatPrice(pkg.price)})
            : ctx.trMsg('assistant_buy_confirm', params: {
                'price': formatPrice(pkg.price),
                'days': '${pkg.days}',
              })),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('assistant_buy')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _buyingId = pkg.id);
    try {
      final result = await widget.service.buyPackage(pkg.id);
      if (!mounted) return;
      Navigator.pop(context, result);
    } on AssistantException catch (e) {
      if (!mounted) return;
      setState(() => _buyingId = null);
      if (e.isInsufficientBalance) {
        final bal = (e.details['balance'] as num?)?.toInt();
        if (bal != null) setState(() => _balance = bal);
        _showInsufficient();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('assistant_err_unavailable'))),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _buyingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('assistant_err_unavailable'))),
      );
    }
  }

  void _showInsufficient() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('assistant_insufficient')),
        action: SnackBarAction(
          label: context.tr('assistant_topup'),
          onPressed: () {
            Navigator.pop(context);
            widget.onTopUp();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (widget.limitReached) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('assistant_limit_title'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.trMsg('assistant_limit_body',
                          params: {'count': '${s.freeDailyLimit}'}),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: Color(0xFFF9A825)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('assistant_pro_sheet_title'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('assistant_pro_benefits'),
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
            if (s.pro && s.paidUntil != null) ...[
              const SizedBox(height: 8),
              Text(
                s.lifetime
                    ? context.tr('assistant_pro_unlimited')
                    : context.trMsg('assistant_pro_until',
                        params: {'date': formatDateShort(s.paidUntil)}),
                style: const TextStyle(
                    fontSize: 13, color: AvaLight.ok),
              ),
            ],
            const SizedBox(height: 14),
            for (final pkg in s.packages)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PackageTile(
                  pkg: pkg,
                  busy: _buyingId == pkg.id,
                  disabled: _buyingId != null,
                  onTap: () => _buy(pkg),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 18, color: Colors.black54),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.trMsg('assistant_balance',
                        params: {'amount': formatPrice(_balance)}),
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onTopUp();
                  },
                  child: Text(context.tr('assistant_topup')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.pkg,
    required this.busy,
    required this.disabled,
    required this.onTap,
  });

  final AssistantPackage pkg;
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final perDay = pkg.days > 0 ? (pkg.price / pkg.days).round() : 0;
    return Material(
      color: pkg.promo ? AvaLight.surface2 : const Color(0xFFF6F6F6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: pkg.promo ? AppColors.primaryDark : Colors.black12,
              width: pkg.promo ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          pkg.oneTime
                              ? context.tr('assistant_onetime_label')
                              : context.trMsg('assistant_days',
                                  params: {'count': '${pkg.days}'}),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        if (pkg.promo) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              context.tr('assistant_promo'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pkg.oneTime
                          ? context.tr('assistant_onetime_sub')
                          : context.trMsg('assistant_per_day',
                              params: {'amount': formatPrice(perDay)}),
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  formatMoney(pkg.price),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
