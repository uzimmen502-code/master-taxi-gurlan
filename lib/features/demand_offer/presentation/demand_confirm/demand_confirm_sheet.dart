// «ШУНДАЙ ТУШУНДИК» — юборишдан олдинги тасдиқлаш қадами (13.4.6).
//
// НЕГА БУ ЭКРАН БОР (концепция):
//   «Юборишдан олдин фойдаланувчига AVA нимани тушунгани қисқа
//    кўрсатилади… Бу нотўғри тушуниш натижасида номос одамларга
//    юборишнинг олдини олади.»
//
// Яъни бу шунчаки «тасдиқлайсизми?» ойнаси эмас. Унинг вазифаси —
// СПАМНИ ОЛДИНИ ОЛИШ: агар AVA «кран оқяпти»ни фотограф деб тушунган
// бўлса, фойдаланувчи буни ШУ ЕРДА кўради ва тузатади. Акс ҳолда
// сўров 20 та фотографга кетиб, уларнинг ҳаммаси push олади.
//
// Шунинг учун экран ЎТКАЗИБ ЮБОРИЛМАЙДИ (`barrierDismissible: false`
// эмас, лекин «Юбориш» фақат шу ердан босилади).

import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/ava_tokens.dart';
import '../../ui_adapters/demand_ui_adapter.dart';

/// Тасдиқлаш варақасини кўрсатади.
///
/// Қайтаради: `true` — юборилсин, `false`/`null` — тузатишга қайтилди.
Future<bool?> showDemandConfirmSheet(
  BuildContext context, {
  required List<ConfirmRow> rows,
  required bool isSending,
  void Function(String field)? onEditField,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DemandConfirmSheet(
      rows: rows,
      isSending: isSending,
      onEditField: onEditField,
    ),
  );
}

class DemandConfirmSheet extends StatelessWidget {
  const DemandConfirmSheet({
    super.key,
    required this.rows,
    this.isSending = false,
    this.onEditField,
  });

  final List<ConfirmRow> rows;
  final bool isSending;
  final void Function(String field)? onEditField;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;

    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            Text(
              context.tr('confirm_title'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('confirm_hint'),
              style: TextStyle(fontSize: 12, color: c.ink2),
            ),
            const SizedBox(height: 14),

            // Қаторлар — ҳар бири босилса тузатишга олиб боради.
            Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.line),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i += 1) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: c.line),
                    _row(context, rows[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isSending
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.ink,
                      side: BorderSide(color: c.line),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(context.tr('confirm_edit')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: isSending
                        ? null
                        : () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.brand,
                      foregroundColor: c.brandInk,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isSending
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.brandInk,
                            ),
                          )
                        : Text(context.tr('request_send')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, ConfirmRow row) {
    final c = context.ava;
    final editable = row.editField != null && onEditField != null;

    return InkWell(
      onTap: editable
          ? () {
              Navigator.of(context).pop(false);
              onEditField!(row.editField!);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            if (row.icon != null) ...[
              Icon(row.icon, size: 16, color: c.ink3),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(row.labelKey),
                    style: TextStyle(fontSize: 11, color: c.ink3),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    row.value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
            if (editable)
              Icon(Icons.edit_outlined, size: 14, color: c.ink3),
          ],
        ),
      ),
    );
  }
}
