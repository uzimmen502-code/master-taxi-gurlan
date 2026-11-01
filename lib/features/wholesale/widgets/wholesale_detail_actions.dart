import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';

/// Пастки тугмаларнинг сутли (молочный) ранги ва ёзуви (эга, 2026-11-01).
const Color kWholesaleMilk = Color(0xFFF6EFE2);
const Color kWholesaleMilkInk = Color(0xFF2A2118);

/// «Буюртма ёзиш» кўринсинми: сотувчи маълум ва бу ЎЗ эълоним эмас (рақамлар канон шаклда
/// солиштирилади: 9 хонали эски ёзув = 998 + 9). Меҳмонга кўринади — босганда рўйхатдан ўтишга
/// таклиф қилинади (сервер ҳам телефонсиз сессияни рад этади).
bool wholesaleShowWriteOrder({required String myUid, required String sellerId}) {
  final seller = canonicalPhoneId(sellerId);
  if (seller.isEmpty) return false;
  return myUid.isEmpty || canonicalPhoneId(myUid) != seller;
}

/// Маҳсулот тафсилоти пастки панели (эга қарори 2026-11-01): БИР қаторда
/// «Қўнғироқ қилиш» (сутли чизиқли) ва «Буюртма ёзиш» (тўлиқ сутли — асосий амал:
/// миқдор ва шартлар чатда келишилади). Ўз маҳсулотида «Буюртма ёзиш» йўқ — қўнғироқ
/// тўлиқ кенгликда (аввалги кўриниш).
class WholesaleDetailActions extends StatelessWidget {
  const WholesaleDetailActions({
    super.key,
    required this.onCall,
    required this.onWriteOrder,
    this.showWriteOrder = true,
    this.writeBusy = false,
  });

  final VoidCallback onCall;
  final VoidCallback onWriteOrder;
  final bool showWriteOrder;

  /// Чат очилмоқда — тугма бир марта босилсин.
  final bool writeBusy;

  static const _labelStyle = TextStyle(fontWeight: FontWeight.w700, fontSize: 15);
  static final _shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

  @override
  Widget build(BuildContext context) {
    final call = showWriteOrder
        ? OutlinedButton.icon(
            key: const ValueKey('wholesale-call'),
            onPressed: onCall,
            style: OutlinedButton.styleFrom(
              foregroundColor: kWholesaleMilk,
              side: const BorderSide(color: kWholesaleMilk, width: 1.5),
              shape: _shape,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: const Icon(Icons.call, size: 20),
            label: _label(context.tr('wholesale_call')),
          )
        : FilledButton.icon(
            key: const ValueKey('wholesale-call'),
            onPressed: onCall,
            style: FilledButton.styleFrom(
              backgroundColor: kWholesaleMilk,
              foregroundColor: kWholesaleMilkInk,
              shape: _shape,
            ),
            icon: const Icon(Icons.call),
            label: _label(context.tr('wholesale_call')),
          );
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(child: call),
          if (showWriteOrder) ...[
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('wholesale-write-order'),
                onPressed: writeBusy ? null : onWriteOrder,
                style: FilledButton.styleFrom(
                  backgroundColor: kWholesaleMilk,
                  foregroundColor: kWholesaleMilkInk,
                  disabledBackgroundColor: kWholesaleMilk.withValues(alpha: 0.6),
                  disabledForegroundColor: kWholesaleMilkInk,
                  shape: _shape,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: writeBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: kWholesaleMilkInk))
                    : const Icon(Icons.chat_bubble_outline, size: 20),
                label: _label(context.tr('deal_chat_write_order')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Тор экранда (320 dp) икки тугма ёнма-ён: матн кичраяди, кесилмайди.
  Widget _label(String s) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(s, maxLines: 1, style: _labelStyle),
      );
}
