import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../business_map/data/business_repository.dart';

/// Шикоят сабаби: [value] — серверга кетадиган қиймат, [labelKey] — экрандаги матн калити.
/// [needsComment] — танланса изоҳ сўралади (сервер ҳам талаб қилади).
typedef ComplaintReason = ({String value, String labelKey, bool needsComment});

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
}) {
  const reasons = <ComplaintReason>[
    (value: 'Алдамчи эълон', labelKey: 'ad_report_reason_fraud', needsComment: false),
    (value: 'Телефон нотўғри', labelKey: 'ad_report_reason_phone', needsComment: false),
    (value: 'Спам / Такрорий', labelKey: 'ad_report_reason_spam', needsComment: false),
    (value: 'Ҳақоратли матн', labelKey: 'ad_report_reason_abuse', needsComment: false),
  ];
  final send = submit ?? BusinessRepository().submitComplaint;
  return showComplaintSheet(
    context,
    reasons: reasons,
    keyPrefix: 'shop_report',
    send: (reason, _) => send(targetType: targetType, targetId: targetId, reason: reason),
  );
}

/// Умумий шикоят варағи (дўкон, ресторан/таом, кўчмас мулк): сабаб рўйхати → (керак бўлса изоҳ) → [send] →
/// натижа SnackBar'да. Хато матни ҳеч қачон хом кўрсатилмайди (25-банд): сервер коди тушунарли калитга.
/// [ownKey] — ўзига шикоят (`COMPLAINT_OWN`) матни.
Future<void> showComplaintSheet(
  BuildContext context, {
  required List<ComplaintReason> reasons,
  required Future<void> Function(String reason, String comment) send,
  String keyPrefix = 'complaint',
  String ownKey = 'shop_report_own',
}) async {
  final picked = await showModalBottomSheet<ComplaintReason>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(ctx.tr('ad_report_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          // Кичик экран / катта шрифтда рўйхат варақ ичида айланади (ортиб кетмайди).
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final r in reasons)
                  ListTile(
                    key: ValueKey('${keyPrefix}_${r.labelKey}'),
                    title: Text(ctx.tr(r.labelKey)),
                    onTap: () => Navigator.pop(ctx, r),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  var comment = '';
  if (picked.needsComment) {
    final text = await _askComment(context);
    if (text == null || !context.mounted) return;
    comment = text;
  }
  String key;
  var ok = false;
  try {
    await send(picked.value, comment);
    key = 'ad_report_sent';
    ok = true;
  } on FirebaseFunctionsException catch (e) {
    final code = e.details is Map ? '${(e.details as Map)['code'] ?? ''}' : '';
    key = switch ((e.code, code)) {
      ('unauthenticated', _) => 'shop_report_need_login',
      (_, 'COMPLAINT_OWN') => ownKey,
      (_, 'COMPLAINT_LIMIT') || ('resource-exhausted', _) => 'ad_report_limit',
      (_, 'COMPLAINT_TARGET_NOT_FOUND') => 'content_report_unavailable',
      _ => 'shop_report_failed',
    };
  } catch (e) {
    debugPrint('[Complaint] $e');
    key = 'shop_report_failed';
  }
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(context.tr(key)), backgroundColor: ok ? null : Colors.red),
  );
}

/// «Бошқа» сабаб учун изоҳ (3…300 белги — сервердаги чегара билан бир хил).
Future<String?> _askComment(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _CommentDialog());

class _CommentDialog extends StatefulWidget {
  const _CommentDialog();

  @override
  State<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<_CommentDialog> {
  // Контроллер диалог билан бирга яшайди (ёпилиш анимациясида ҳам) — ташқарида dispose қилинмайди.
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _ctrl.text.trim();
    return AlertDialog(
      title: Text(context.tr('content_report_comment_title')),
      content: TextField(
        key: const ValueKey('complaint_comment_field'),
        controller: _ctrl,
        autofocus: true,
        maxLength: 300,
        maxLines: 3,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: context.tr('content_report_comment_hint'),
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        FilledButton(
          key: const ValueKey('complaint_comment_send'),
          onPressed: text.length < 3 ? null : () => Navigator.pop(context, text),
          child: Text(context.tr('content_report_send')),
        ),
      ],
    );
  }
}
