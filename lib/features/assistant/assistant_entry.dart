import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/utils/chatgpt_launcher.dart';
import '../../core/utils/formatters.dart';
import '../profile/screens/profile_screen.dart';
import 'screens/assistant_chat_screen.dart';
import 'widgets/assistant_gpt_colors.dart';

/// Home'даги «ChatGPT + AVA AI» тугмаси — кириш нуқтаси (эга қарори,
/// 2026-09-21/22):
///
/// 1. Рўйхатдан ўтмаган (телефон йўқ) — тарифлар + рўйхатдан ўтиш тавсияси;
///    ChatGPT иловаси бўлса — уни очиш имкони (AVA чат серверда телефон
///    талаб қилади).
/// 2. Рўйхатдан ўтган + қурилмада ChatGPT иловаси бор — танлов: AVA AI
///    (тарифлар кўрсатилади) ёки ўз обунаси (Plus ва ҳ.к.). Обуна
///    даражасини илова била олмайди — фақат илова ўрнатилганини текширади.
/// 3. Рўйхатдан ўтган, ChatGPT иловаси йўқ — тўғридан AVA чат.
///
/// Дизайн — ChatGPT услуби ([GptColors], Inter): нейтрал ранглар, тариф
/// қаторлари, битта асосий тугма.
Future<void> openAssistantEntry(
  BuildContext context, {
  required String phone,
  required Future<void> Function(Widget screen) push,
}) async {
  final registered = phoneDigits(phone).length >= 9;
  final chatGptInstalled = await isChatGptAppInstalled();
  if (!context.mounted) return;

  if (registered && !chatGptInstalled) {
    await push(AssistantChatScreen(phone: phone));
    return;
  }

  final choice = await showModalBottomSheet<_EntryChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EntrySheet(
      registered: registered,
      chatGptInstalled: chatGptInstalled,
    ),
  );
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case _EntryChoice.ava:
      await push(AssistantChatScreen(phone: phone));
    case _EntryChoice.register:
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
    case _EntryChoice.chatGpt:
      final ok = await openChatGptApp();
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('chatgpt_open_failed'))),
        );
      }
  }
}

enum _EntryChoice { ava, register, chatGpt }

/// Тарифлар — Home варақасида матн сифатида (сервер `settings/assistant`
/// пакетларини ўзгартирса, шу рўйхатни ҳам янгилаш керак).
const _kPlusPackages = [
  (days: 7, price: 15000, promo: false),
  (days: 15, price: 25000, promo: false),
  (days: 30, price: 30000, promo: true),
];

class _EntrySheet extends StatelessWidget {
  const _EntrySheet({required this.registered, required this.chatGptInstalled});

  final bool registered;
  final bool chatGptInstalled;

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Катта тизим шрифтида ҳам ихчам қолсин (ChatGPT варақалари каби).
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.1)),
      child: Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height -
            MediaQuery.paddingOf(context).top -
            24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Сарлавҳа
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.sendBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, color: c.sendFg, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('home_module_chatgpt'),
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        registered
                            ? context.tr('assistant_choose_title')
                            : context.tr('assistant_guest_title'),
                        style: GoogleFonts.inter(fontSize: 12.5, color: c.subtle),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // AVA AI картаси + тарифлар — картанинг ўзи босилади (тугмасиз).
            Material(
              color: c.bubble,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: registered
                  ? () => Navigator.pop(context, _EntryChoice.ava)
                  : null,
              child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('assistant_choose_ava_desc'),
                          style: GoogleFonts.inter(
                              fontSize: 13, color: c.text, height: 1.35),
                        ),
                      ),
                      if (registered) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.chevron_right_rounded, color: c.subtle),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: c.border),
                  const SizedBox(height: 4),
                  _TariffRow(
                    label: context.tr('assistant_tariff_free_label'),
                    value: context.tr('assistant_tariff_free_value'),
                  ),
                  for (final p in _kPlusPackages)
                    _TariffRow(
                      label: context.trMsg('assistant_tariff_plus',
                          params: {'count': '${p.days}'}),
                      value: formatMoney(p.price),
                      promo: p.promo,
                    ),
                  if (!registered) ...[
                    const SizedBox(height: 10),
                    Text(
                      context.tr('assistant_guest_note'),
                      style: GoogleFonts.inter(
                          fontSize: 12.5, color: c.subtle, height: 1.35),
                    ),
                  ],
                  if (!registered) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 44,
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, _EntryChoice.register),
                        style: FilledButton.styleFrom(
                          backgroundColor: c.sendBg,
                          foregroundColor: c.sendFg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          context.tr('assistant_guest_register'),
                          style: GoogleFonts.inter(
                              fontSize: 14.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              ),
              ),
            ),

            // ChatGPT иловаси — ўз обунаси
            if (chatGptInstalled) ...[
              const SizedBox(height: 10),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.pop(context, _EntryChoice.chatGpt),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.border),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                    child: Row(
                      children: [
                        Icon(Icons.open_in_new_rounded, color: c.text, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('assistant_choose_gpt_title'),
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: c.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                context.tr('assistant_choose_gpt_sub'),
                                style: GoogleFonts.inter(
                                    fontSize: 12, color: c.subtle, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: c.subtle),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

class _TariffRow extends StatelessWidget {
  const _TariffRow({
    required this.label,
    required this.value,
    this.promo = false,
  });

  final String label;
  final String value;
  final bool promo;

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 13, color: c.text),
                ),
                if (promo)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      context.tr('assistant_promo'),
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
        ],
      ),
    );
  }
}
