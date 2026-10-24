import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n_extension.dart';

/// Танишув боти — Telegram'даги эски канал.
///
/// Танишув модули иловага кўчирилди ([DatingHomeScreen]), лекин бот ишлаб
/// турибди ва унда одам бор. Шунинг учун у ЙЎҚОЛМАЙДИ — модулнинг ўз
/// экрани ичидан очилади (эга қарори: «илова ичидаги DatingHomeScreen'ни
/// ботга улаш керак»).
const datingTelegramBotUrl = 'https://t.me/bilish_tanish_bot';

/// Ботни ташқи иловада очади. Telegram ўрнатилмаган бўлса — огоҳлантириш.
Future<void> openDatingTelegramBot(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failedText = context.tr('dating_telegram_failed');
  try {
    final opened = await launchUrl(
      Uri.parse(datingTelegramBotUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger?.showSnackBar(
        SnackBar(content: Text(failedText)),
      );
    }
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: Text(failedText)),
    );
  }
}

/// AppBar'даги бот тугмаси — танишув экранининг ҳар бир ҳолатида
/// (онбординг, модерация кутиш, фаол профил) бир хил жойда туради.
class DatingBotButton extends StatelessWidget {
  const DatingBotButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => openDatingTelegramBot(context),
      tooltip: context.tr('dating_telegram_bot'),
      icon: const Icon(Icons.send_rounded),
    );
  }
}
