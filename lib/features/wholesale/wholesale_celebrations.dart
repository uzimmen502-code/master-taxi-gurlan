// Улгуржи сотувчи табриклари (эга, 2026-10-31):
//   «Улгуржи сотувчи … тасдиқланганда табрик чиқсинми?» — «ҳа»;
//   «Улгуржи сотувчига биринчи буюртма келганда» — «табрик бўлсин».
//
// Иккаласи ҳам [CelebrationOnce] билан шу қурилмада БИР МАРТА.

import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/celebration_dialog.dart';
import 'models/wholesale_seller.dart';

/// Тасдиқ шу муддат ичида бўлсагина табрик: янгилангандан кейин эски (аллақачон
/// ишлаётган) сотувчиларга «тасдиқландингиз» чиқмасин.
const wholesaleSellerApprovalFreshFor = Duration(days: 7);

String wholesaleSellerApprovedKey(String phone) =>
    'wholesale_seller_approved_${canonicalPhoneId(phone)}';

String wholesaleFirstOrderKey(String sellerId) =>
    'wholesale_first_order_${canonicalPhoneId(sellerId)}';

/// Тасдиқ янгими: `approved`, `approvedAt` бор ва [wholesaleSellerApprovalFreshFor] дан эски эмас.
/// `approvedAt` келажакда бўлса (соат фарқи) — янги деб ҳисобланади.
@visibleForTesting
bool isFreshWholesaleApproval(WholesaleSeller seller, DateTime now) {
  final at = seller.approvedAt;
  if (!seller.isApproved || at == null) return false;
  return now.difference(at) <= wholesaleSellerApprovalFreshFor;
}

/// Сотувчи тасдиқланди — табрик. `true` — кўрсатилди.
Future<bool> celebrateWholesaleSellerApprovedOnce(
  BuildContext context, {
  required WholesaleSeller seller,
  DateTime? now,
}) async {
  if (canonicalPhoneId(seller.phone).length < 9) return false;
  if (!isFreshWholesaleApproval(seller, now ?? DateTime.now())) return false;
  if (!await CelebrationOnce.claim(wholesaleSellerApprovedKey(seller.phone))) return false;
  if (!context.mounted) return false;
  await showCelebration(
    context,
    icon: Icons.storefront_rounded,
    title: context.tr('wholesale_seller_approved_title'),
    subtitle: context.tr('wholesale_seller_approved_sub'),
    buttonLabel: context.tr('celebration_continue'),
  );
  return true;
}

/// Сотувчининг биринчи буюртмаси — табрик. [orderCount] — сотувчида кўрилган
/// буюртмалар сони (камида 2 тасини ўқиш кифоя).
///
/// Қоида: 0 — ҳеч нарса (белги қўйилмайди, биринчи буюртма кутилади); 1 — табрик;
/// 2+ — табрик ЙЎҚ ва белги қўйилади (биринчи буюртма аллақачон ўтиб кетган —
/// кейинчалик ҳам чиқмасин). `true` — кўрсатилди.
Future<bool> celebrateWholesaleFirstOrderOnce(
  BuildContext context, {
  required String sellerId,
  required int orderCount,
}) async {
  if (orderCount <= 0 || canonicalPhoneId(sellerId).length < 9) return false;
  if (!await CelebrationOnce.claim(wholesaleFirstOrderKey(sellerId))) return false;
  if (orderCount != 1 || !context.mounted) return false;
  await showCelebration(
    context,
    icon: Icons.inventory_2_rounded,
    title: context.tr('wholesale_first_order_title'),
    subtitle: context.tr('wholesale_first_order_sub'),
    buttonLabel: context.tr('wholesale_first_order_view'),
  );
  return true;
}
