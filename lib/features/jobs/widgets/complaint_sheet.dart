import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// Шикоят сабаби: серверга ВА модераторга ҳар доим бир хил (кирилл) матн
/// кетади, экранда эса фойдаланувчи тилидаги ёрлиқ кўринади.
typedef _Reason = ({String payload, String labelKey});

const List<_Reason> _reasons = [
  (payload: '🚫 Алдамчи эълон', labelKey: 'ad_report_reason_fraud'),
  (payload: '📞 Телефон нотўғри', labelKey: 'ad_report_reason_phone'),
  (payload: '🗑️ Спам / Такрорий', labelKey: 'ad_report_reason_spam'),
  (payload: '⚠️ Ҳақоратли матн', labelKey: 'ad_report_reason_abuse'),
];

/// Эълонга шикоят сабабини танлаш bottom sheet'и. Қайтиш: сервер учун матн.
Future<String?> showComplaintSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            sheetCtx.tr('ad_report_title'),
            style: const TextStyle(
                fontSize: AppText.titleMedium, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ..._reasons.map((r) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                    '${r.payload.split(' ').first} ${sheetCtx.tr(r.labelKey)}',
                    style: const TextStyle(fontSize: AppText.bodyLarge)),
                onTap: () => Navigator.of(sheetCtx).pop(r.payload),
              )),
        ],
      ),
    ),
  );
}
