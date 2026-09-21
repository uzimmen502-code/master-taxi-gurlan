import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/chatgpt_launcher.dart';
import '../../core/utils/formatters.dart';
import '../profile/screens/profile_screen.dart';
import 'screens/assistant_chat_screen.dart';

/// Home'даги «AVA ёрдамчиси» тугмаси — кириш нуқтаси (эга қарори, 2026-09-21):
///
/// 1. Рўйхатдан ўтмаган (телефон йўқ) — AVA пакетлари расмий ChatGPT'дан
///    арзонлиги ва рўйхатдан ўтиш тавсияси; ChatGPT иловаси бўлса — уни очиш
///    имкони (AVA чат серверда телефон талаб қилади).
/// 2. Рўйхатдан ўтган + қурилмада ChatGPT иловаси бор — танлов: AVA ёрдамчиси
///    ёки ўз обунаси (Plus ва ҳ.к.). Обуна даражасини илова била олмайди —
///    фақат илова ўрнатилганини текширади, қарор фойдаланувчиники.
/// 3. Рўйхатдан ўтган, ChatGPT иловаси йўқ — тўғридан AVA чат.
Future<void> openAssistantEntry(
  BuildContext context, {
  required String phone,
  required Future<void> Function(Widget screen) push,
}) async {
  final registered = phoneDigits(phone).length >= 9;
  final chatGptInstalled = await isChatGptAppInstalled();
  if (!context.mounted) return;

  if (!registered) {
    await _showGuestDialog(context, chatGptInstalled: chatGptInstalled);
    return;
  }

  if (!chatGptInstalled) {
    await push(AssistantChatScreen(phone: phone));
    return;
  }

  final choice = await showModalBottomSheet<_AssistantChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ChoiceSheet(),
  );
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case _AssistantChoice.ava:
      await push(AssistantChatScreen(phone: phone));
    case _AssistantChoice.chatGpt:
      final ok = await openChatGptApp();
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('chatgpt_open_failed'))),
        );
      }
  }
}

Future<void> _showGuestDialog(
  BuildContext context, {
  required bool chatGptInstalled,
}) async {
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Color(0xFF10A37F)),
          const SizedBox(width: 8),
          Expanded(child: Text(ctx.tr('assistant_title'))),
        ],
      ),
      content: Text(ctx.tr('assistant_guest_body')),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        if (chatGptInstalled)
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'chatgpt'),
            child: Text(ctx.tr('assistant_open_chatgpt_app')),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('close')),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'register'),
          child: Text(ctx.tr('assistant_guest_register')),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (action == 'register') {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  } else if (action == 'chatgpt') {
    await openChatGptApp();
  }
}

enum _AssistantChoice { ava, chatGpt }

class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              context.tr('assistant_choose_title'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _ChoiceTile(
              icon: Icons.auto_awesome_rounded,
              iconColor: AppColors.primaryDark,
              title: context.tr('assistant_choose_ava_title'),
              subtitle: context.tr('assistant_choose_ava_sub'),
              highlighted: true,
              onTap: () => Navigator.pop(context, _AssistantChoice.ava),
            ),
            const SizedBox(height: 10),
            _ChoiceTile(
              icon: Icons.open_in_new_rounded,
              iconColor: const Color(0xFF10A37F),
              title: context.tr('assistant_choose_gpt_title'),
              subtitle: context.tr('assistant_choose_gpt_sub'),
              highlighted: false,
              onTap: () => Navigator.pop(context, _AssistantChoice.chatGpt),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.highlighted,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? const Color(0xFFF1F8E9) : const Color(0xFFF6F6F6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlighted ? AppColors.primaryDark : Colors.black12,
              width: highlighted ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          fontSize: 12.5, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
