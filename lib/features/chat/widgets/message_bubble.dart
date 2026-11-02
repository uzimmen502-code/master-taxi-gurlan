import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/chat_message.dart';
import '../../profile/inbox/inbox_time.dart';

/// Чатдаги битта хабар пуфакчаси (support ва «Буюртма ёзиш» чатлари).
///
/// 2026-11-02 (эга, «Хабарлар»ни такомиллаштириш): пуфакча ичида вақт, меники учун
/// ўқилди белгиси (маълумот бўлса), кенглик экраннинг 78% и билан чекланган, AVA ранглари.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.read,
  });

  final ChatMessage message;

  /// Жорий фойдаланувчи нуқтаи назаридан: бу хабар уники бўлса `true`.
  final bool isMine;

  /// Меники учун: `true` — ўқилди (✓✓), `false` — юборилди (✓), `null` — белги йўқ
  /// (маълумот йўқ, масалан support чат).
  final bool? read;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    // `fromAdmin` — CF тизим хабарлари; қўлда жавоб — `fromPhone` (clientда false).
    final showAdminLabel = !isMine &&
        (message.fromAdmin || phoneDigits(message.fromPhone).length >= 9);
    final at = message.createdAt;
    final fg = isMine ? c.brandInk : c.ink;
    final meta = isMine ? c.brandInk.withValues(alpha: 0.65) : c.ink3;
    // Чат рўйхати кенглигининг 78% и (экран эмас — веб/планшетда ҳам тўғри).
    return LayoutBuilder(builder: (context, box) {
      final maxW = (box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width) * 0.78;
      return _bubble(context, c, showAdminLabel, at, fg, meta, maxW);
    });
  }

  Widget _bubble(BuildContext context, AvaColors c, bool showAdminLabel, DateTime? at, Color fg, Color meta,
      double maxW) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(12, 7, 10, 6),
          decoration: BoxDecoration(
            color: isMine ? c.brand : c.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
            border: isMine ? null : Border.all(color: c.line, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showAdminLabel)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    context.tr('chat_admin_label'),
                    style: AvaText.caption.copyWith(fontWeight: FontWeight.w600, color: c.ok),
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 8,
                children: [
                  Text(message.text, style: AvaText.body.copyWith(fontSize: 15, color: fg)),
                  if (at != null || (isMine && read != null))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (at != null)
                            Text(inboxClock(at),
                                key: const ValueKey('bubble-time'),
                                style: AvaText.caption.copyWith(fontSize: 11, color: meta)),
                          if (isMine && read != null) ...[
                            const SizedBox(width: 3),
                            Icon(read! ? Icons.done_all : Icons.done,
                                key: ValueKey(read! ? 'bubble-read' : 'bubble-sent'),
                                size: 14,
                                color: meta),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Чатдаги кун ажратгичи («Бугун», «Кеча», «31.10.2026»).
class ChatDaySeparator extends StatelessWidget {
  const ChatDaySeparator({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(AvaRadius.chip),
        ),
        child: Text(
          inboxDayLabel(day,
              now: DateTime.now(), today: context.tr('inbox_today'), yesterday: context.tr('inbox_yesterday')),
          style: AvaText.caption.copyWith(color: c.ink2, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

/// Хабарлар (эскидан янгига) → кун ажратгичлари қўшилган қаторлар. Вақти йўқ
/// (ҳозиргина юборилган) хабар олдингисининг кунида қолади.
List<Object?> withDaySeparators<T>(List<T> messages, DateTime? Function(T) at) {
  final out = <Object?>[];
  DateTime? prev;
  for (final m in messages) {
    final t = at(m);
    if (t != null && (prev == null || !inboxSameDay(t, prev))) {
      out.add(ChatDay(t));
      prev = t;
    }
    out.add(m);
  }
  return out;
}

/// [withDaySeparators] қаторидаги ажратгич.
class ChatDay {
  const ChatDay(this.day);
  final DateTime day;
}
