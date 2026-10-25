import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../business_map/data/business_repository.dart';

/// Харидор шикояти: маҳсулот ёки бутун дўкон (эга қарори 2026-10-25). Сабаблар — эълон шикояти билан бир хил
/// (серверга ўзбекча қиймат, экранда фойдаланувчи тилида; админ ва эски шикоятлар билан мос).
///
/// [targetType] — `shop_item` ([targetId] = маҳсулот ID) ёки `shop` ([targetId] = сотувчи телефони).
/// [submit] — тест учун алмаштирилади; бўлмаса `BusinessRepository().submitComplaint`.
Future<void> showShopComplaintSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  Future<void> Function({required String targetType, required String targetId, required String reason})? submit,
}) async {
  const reasons = <(String, String)>[
    ('Алдамчи эълон', 'ad_report_reason_fraud'),
    ('Телефон нотўғри', 'ad_report_reason_phone'),
    ('Спам / Такрорий', 'ad_report_reason_spam'),
    ('Ҳақоратли матн', 'ad_report_reason_abuse'),
  ];
  final reason = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(ctx.tr('ad_report_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          for (final r in reasons)
            ListTile(
              key: ValueKey('shop_report_${r.$2}'),
              title: Text(ctx.tr(r.$2)),
              onTap: () => Navigator.pop(ctx, r.$1),
            ),
        ],
      ),
    ),
  );
  if (reason == null || !context.mounted) return;
  final send = submit ?? BusinessRepository().submitComplaint;
  String key;
  var ok = false;
  try {
    await send(targetType: targetType, targetId: targetId, reason: reason);
    key = 'ad_report_sent';
    ok = true;
  } on FirebaseFunctionsException catch (e) {
    final code = e.details is Map ? '${(e.details as Map)['code'] ?? ''}' : '';
    key = switch ((e.code, code)) {
      ('unauthenticated', _) => 'shop_report_need_login',
      (_, 'COMPLAINT_OWN') => 'shop_report_own',
      (_, 'COMPLAINT_LIMIT') || ('resource-exhausted', _) => 'ad_report_limit',
      _ => 'shop_report_failed',
    };
  } catch (e) {
    debugPrint('[ShopComplaint] $e');
    key = 'shop_report_failed';
  }
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(context.tr(key)), backgroundColor: ok ? null : Colors.red),
  );
}
