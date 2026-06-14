import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/chat_message.dart';

/// Chatda bitta xabar pufakchasi.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;

  /// Joriy foydalanuvchi nuqtai nazaridan: bu xabar uniki bo'lsa `true`.
  /// Admin uchun `fromAdmin == true` bo'lganlar "men yozdim".
  final bool isMine;

  static const _green = AppColors.primaryDark;

  @override
  Widget build(BuildContext context) {
    // `fromAdmin` — CF тизим хабарлари; қўлда жавоб — `fromPhone` (clientда false).
    final showAdminLabel = !isMine &&
        (message.fromAdmin ||
            phoneDigits(message.fromPhone).length >= 9);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showAdminLabel)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                'Админ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isMine ? _green : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.text,
              style: TextStyle(
                color: isMine ? Colors.white : Colors.black87,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
