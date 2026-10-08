import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../realty_tabs.dart';

/// Хато хабарлари ва пакет ҳисоблагичи — бутун бўлим учун БИТТА жой.
///
/// Нега: сервер хатони код билан қайтаради (`functions/realty.js` даги
/// `fail()`), иловада эса ҳар бир экран ўша кодларни ўзича матнга
/// айлантирар эди. Натижада битта код бир экранда тушунарли хабар,
/// бошқасида «Хатолик. Кейинроқ уриниб кўринг.» бўлиб кўринарди.

/// Сервер хато кодини фойдаланувчи тилидаги матнга айлантиради.
///
/// Нотаниш код — умумий хабар: сервер янги код қўшса, илова эски
/// бўлса ҳам тушунарли нарса кўрсатади.
String realtyErrorText(BuildContext context, RealtyException e) {
  switch (e.code) {
    case 'free_limit_reached':
      return context.tr('realty_error_free_limit');
    case 'location_required':
      return context.tr('realty_error_location');
    case 'address_required':
      return context.tr('realty_error_address');
    case 'tier_not_available':
      return context.tr('realty_error_tier_soon');
    case 'insufficient_balance':
      return context.tr('realty_error_balance');
    case 'listing_blocked':
      return context.tr('realty_error_listing_blocked');
    case 'listing_expired':
      return context.tr('realty_error_listing_expired');
    case 'pro_required':
      return context.tr('realty_team_needs_pro');
    case 'member_not_found':
      return context.tr('realty_team_not_found');
    case 'member_has_listings':
      return context.tr('realty_team_has_listings');
    default:
      return context.tr('realty_error_generic');
  }
}

/// Қизил (СРОЧНО рангидаги) хато хабари.
///
/// Биринчи аргумент — `BuildContext` ЭМАС, `ScaffoldMessengerState`:
/// хабар кўпинча `await` дан кейин кўрсатилади, у пайтда эса контекст
/// ишончсиз (экран ёпилган бўлиши мумкин). Чақирувчи messenger'ни
/// `await` дан ОЛДИН олиб қўяди.
void showRealtyError(ScaffoldMessengerState messenger, String text) {
  messenger.showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: RealtyTabs.colorFor(RealtyTier.urgent),
    behavior: SnackBarBehavior.floating,
  ));
}

/// Маълумот хабари; [background] берилса — ўша рангда.
void showRealtyInfo(
  ScaffoldMessengerState messenger,
  String text, {
  Color? background,
}) {
  messenger.showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: background,
    behavior: SnackBarBehavior.floating,
  ));
}

/// Пакет ҳисоблагичи — «Банд объект ўрни: 12 / 25» (концепция,
/// 5-бўлим: «қанча объект ўрни ва муддат қолгани доим кўриниб туради»).
///
/// [compact] — эълон қўшиш экранининг тагидаги ингичка йўлакча;
/// иккита алоҳида виджет ўрнига битта, чунки матн ва мантиқ бир хил
/// эди (фарқи фақат ўлчамда эди).
class RealtyQuotaBar extends StatelessWidget {
  const RealtyQuotaBar({
    super.key,
    required this.quota,
    this.compact = false,
  });

  final RealtyQuota quota;
  final bool compact;

  /// «Банд ўрин: 2 / 2» — иккита экранда бир хил бўлиши учун шу ерда.
  static String label(BuildContext context, RealtyQuota quota) =>
      '${context.tr(quota.isPro ? 'realty_pro_quota' : 'realty_my_free_slots')}'
      ': ${quota.used} / ${quota.limit}';

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final full = quota.isFull;
    final accent = full ? RealtyTabs.colorFor(RealtyTier.urgent) : c.ink3;
    final icon = quota.isPro
        ? Icons.workspace_premium_outlined
        : Icons.home_outlined;

    if (compact) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label(context, quota),
              style: TextStyle(
                fontSize: AppText.labelTiny,
                color: accent,
                fontWeight: full ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    final days = quota.proDaysLeft;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: full ? RealtyTabs.colorFor(RealtyTier.urgent) : c.line,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label(context, quota),
                  style: TextStyle(
                    fontSize: AppText.bodyMedium,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                if (quota.isPro && days != null)
                  Text(
                    '${context.tr('realty_expires_in')}: $days '
                    '${context.tr('realty_days_short')}',
                    style: TextStyle(
                      fontSize: AppText.labelSmall,
                      color: c.ink3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
