import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../services/tv_ad_service.dart';

/// «Эълон» тариф (5) × муддат (7/15/30 кун) × қамров (туман/вилоят/
/// республика) — AVA TV тариф жадвали. Жорий wallet баланси кўринади;
/// етарли бўлмаса огоҳлантириш чиқади.
///
/// Видео жойлаш экранида ҳам, эълонни узайтириш ойнасида ҳам шу битта
/// виджет ишлатилади (аввал иккита нусха бор эди).
class TvAdTierPicker extends StatelessWidget {
  const TvAdTierPicker({
    super.key,
    required this.selectedTier,
    required this.selectedDays,
    required this.pricing,
    required this.walletBalance,
    required this.onTierChanged,
    required this.onDaysChanged,
    this.selectedScope = 'district',
    this.scopeMultiplier = tvAdScopeMultiplierDefault,
    this.onScopeChanged,
    this.districtLabel = '',
    this.regionLabel = '',
    this.enabled = true,
  });

  final String selectedTier;
  final int selectedDays;
  final Map<String, Map<int, int>> pricing;
  final int walletBalance;
  final ValueChanged<String> onTierChanged;
  final ValueChanged<int> onDaysChanged;

  /// Қамров — `null` берилса (масалан узайтириш ойнасида, қамров
  /// ўзгартирилмайди) селектор умуман кўрсатилмайди.
  final String selectedScope;
  final Map<String, num> scopeMultiplier;
  final ValueChanged<String>? onScopeChanged;
  final String districtLabel;
  final String regionLabel;

  /// `false` — юбориш жараёнида танловни қотириб қўяди.
  final bool enabled;

  int basePriceFor(String tier, int days) =>
      pricing[tier]?[days] ?? tvAdTierPricingDefault[tier]?[days] ?? 0;

  int priceFor(String tier, int days) {
    final base = basePriceFor(tier, days);
    final mult = scopeMultiplier[selectedScope] ??
        tvAdScopeMultiplierDefault[selectedScope] ??
        1;
    return (base * mult).round();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPrice = priceFor(selectedTier, selectedDays);
    final insufficient = selectedPrice > 0 && walletBalance < selectedPrice;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onScopeChanged != null) ...[
            Text(
              context.tr('tv_ad_scope_title'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            for (final scope in tvAdScopes)
              _ScopeTile(
                scope: scope,
                selected: scope == selectedScope,
                sublabel: _scopeSublabel(context, scope),
                multiplier: scopeMultiplier[scope] ??
                    tvAdScopeMultiplierDefault[scope] ??
                    1,
                onTap: enabled ? () => onScopeChanged!(scope) : null,
              ),
            const SizedBox(height: 6),
          ],
          Text(
            context.tr('tv_ad_tier_title'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final tier in tvAdTiers)
            _TierTile(
              tier: tier,
              selected: tier == selectedTier,
              price: priceFor(tier, selectedDays),
              onTap: enabled ? () => onTierChanged(tier) : null,
            ),
          const SizedBox(height: 6),
          Text(
            context.tr('tv_ad_duration_title'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final days in tvAdDurationOptions)
                _DurationChip(
                  days: days,
                  price: priceFor(selectedTier, days),
                  selected: days == selectedDays,
                  onTap: enabled ? () => onDaysChanged(days) : null,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context
                      .tr('tv_ad_wallet_balance')
                      .replaceAll('{balance}', formatMoney(walletBalance)),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          if (insufficient) ...[
            const SizedBox(height: 6),
            Text(
              context.tr('tv_ad_insufficient_balance'),
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _scopeSublabel(BuildContext context, String scope) {
    switch (scope) {
      case 'district':
        return districtLabel.isNotEmpty
            ? districtLabel
            : context.tr('tv_ad_scope_district_hint');
      case 'region':
        return regionLabel.isNotEmpty
            ? regionLabel
            : context.tr('tv_ad_scope_region_hint');
      default:
        return context.tr('tv_ad_scope_national_hint');
    }
  }
}

class _ScopeTile extends StatelessWidget {
  const _ScopeTile({
    required this.scope,
    required this.selected,
    required this.sublabel,
    required this.multiplier,
    required this.onTap,
  });

  final String scope;
  final bool selected;
  final String sublabel;
  final num multiplier;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00E676).withValues(alpha: 0.14)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF00E676) : Colors.grey.shade300,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? const Color(0xFF00A853) : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('tv_ad_scope_$scope'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  Text(
                    sublabel,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            if (multiplier != 1)
              Text(
                '×${multiplier % 1 == 0 ? multiplier.toInt() : multiplier}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }
}

class _TierTile extends StatelessWidget {
  const _TierTile({
    required this.tier,
    required this.selected,
    required this.price,
    required this.onTap,
  });

  final String tier;
  final bool selected;
  final int price;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00E676).withValues(alpha: 0.14)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF00E676) : Colors.grey.shade300,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? const Color(0xFF00A853) : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('tv_ad_tier_$tier'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  Text(
                    context.tr('tv_ad_tier_${tier}_hint'),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Text(
              price > 0 ? formatMoney(price) : context.tr('tv_ad_free'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.days,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  final int days;
  final int price;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      selectedColor: const Color(0xFF00E676),
      label: Text(
        price > 0
            ? '$days ${context.tr('tv_ad_days_suffix')} · ${formatMoney(price)}'
            : '$days ${context.tr('tv_ad_days_suffix')} · ${context.tr('tv_ad_free')}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? Colors.black : Colors.black87,
        ),
      ),
    );
  }
}
