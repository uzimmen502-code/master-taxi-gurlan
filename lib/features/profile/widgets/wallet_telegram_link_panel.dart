import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

/// Telegram бот орқали ҳамён тўлдириш — бир тугмали боғлаш.
class WalletTelegramLinkPanel extends StatefulWidget {
  const WalletTelegramLinkPanel({super.key, required this.phone});

  final String phone;

  @override
  State<WalletTelegramLinkPanel> createState() =>
      _WalletTelegramLinkPanelState();
}

class _WalletTelegramLinkPanelState extends State<WalletTelegramLinkPanel> {
  /// Prod bot (setup doc). API javob берса шу ўрнига ёзилади.
  static const _fallbackBotUsername = 'AvaZonaWalletBot';

  bool _busy = false;
  String? _code;
  String? _botUsername;
  String? _fallbackHint;

  String get _uid => canonicalPhoneId(widget.phone);

  String get _resolvedBotUsername {
    final u = (_botUsername ?? '').trim();
    return u.isNotEmpty ? u : _fallbackBotUsername;
  }

  Future<Map<String, dynamic>?> _createLinkCode() async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('createTelegramLinkCode')
        .call({'phone': widget.phone});
    return Map<String, dynamic>.from(res.data as Map? ?? {});
  }

  Future<void> _linkAndOpen() async {
    setState(() {
      _busy = true;
      _fallbackHint = null;
    });
    try {
      final data = await _createLinkCode();
      final code = data?['code'] as String?;
      final deepLink = data?['deepLink'] as String?;
      final botUsername = data?['botUsername'] as String?;

      if (!mounted) return;
      setState(() {
        _code = code;
        _botUsername = botUsername;
      });

      final opened = await _openUrl(deepLink) ||
          await _openUrl(
            (botUsername != null && botUsername.isNotEmpty)
                ? 'https://t.me/$botUsername'
                : null,
          );

      if (!mounted) return;
      if (!opened) {
        setState(() {
          _fallbackHint =
              'Telegram очилмади. Кодни нусхалаб ботга /link билан юборинг.';
        });
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message ?? e.code),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openBot() async {
    await _openUrl('https://t.me/$_resolvedBotUsername');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(_uid)
              .snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data();
            final telegramId = (data?['telegramId'] ?? '').toString().trim();
            final tgUser =
                (data?['telegramUsername'] ?? '').toString().trim();
            final linked = telegramId.isNotEmpty;

            if (linked) {
              return _linkedBody(tgUser);
            }
            return _unlinkedBody();
          },
        ),
      ),
    );
  }

  Widget _linkedBody(String tgUser) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Telegram орқали тўлдириш',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tgUser.isNotEmpty
                    ? 'Боғланган: @$tgUser'
                    : 'Telegram боғланган',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Ботда /deposit билан тўлдиринг — админ тасдиқлагач ҳамёнга тушади.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _openBot,
          icon: const Icon(Icons.telegram),
          label: const Text('Ҳамённи тўлдириш'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
        ),
        TextButton(
          onPressed: _busy ? null : _linkAndOpen,
          child: const Text('Қайта боғлаш'),
        ),
      ],
    );
  }

  Widget _unlinkedBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Telegram орқали тўлдириш',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          'Бир босиш — бот очилади ва ҳамён боғланади. '
          'Кейин картага ўтказиб, чек юборинг.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _linkAndOpen,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.telegram),
          label: const Text('Ҳамённи тўлдириш'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
        ),
        if (_fallbackHint != null || _code != null) ...[
          const SizedBox(height: 12),
          if (_fallbackHint != null)
            Text(
              _fallbackHint!,
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          if (_code != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    'Код: $_code',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Нусха',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _code!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Код нусхаланди')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            if (_botUsername != null && _botUsername!.isNotEmpty)
              Text(
                'Ботда: /link $_code',
                style: const TextStyle(fontSize: 13),
              ),
          ],
        ],
      ],
    );
  }
}
