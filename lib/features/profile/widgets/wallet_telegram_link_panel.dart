import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import 'wallet_amount_sheet.dart';

/// Telegram бот орқали ҳамён тўлдириш — бир тугмали боғлаш.
///
/// [enabled] `false` бўлса (бот ўчиқ ёки депозит картаси созланмаган — қаранг
/// `getWalletTopUpStatus`) тугмалар ўчиқ: фойдаланувчи ботга боришдан олдин
/// сабабини билади.
class WalletTelegramLinkPanel extends StatefulWidget {
  const WalletTelegramLinkPanel({
    super.key,
    required this.phone,
    this.enabled = true,
    this.suggestedAmount,
    this.maxAmount = 0,
    this.pickAmount,
    this.openUrl,
  });

  final String phone;
  final bool enabled;

  /// Етишмаётган сумма (харид экранидан келса) ва бир сўровнинг юқори чегараси
  /// (`getWalletTopUpStatus`, 0 — номаълум).
  final int? suggestedAmount;
  final int maxAmount;

  /// Тест учун алмаштириладиган: сумма танлаш ва ҳаволани очиш.
  final Future<int?> Function(BuildContext context, int? suggested, int max)? pickAmount;
  final Future<bool> Function(String url)? openUrl;

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
  bool _notOpened = false;

  String get _uid => canonicalPhoneId(widget.phone);

  String get _resolvedBotUsername {
    final u = (_botUsername ?? '').trim();
    return u.isNotEmpty ? u : _fallbackBotUsername;
  }

  Future<Map<String, dynamic>?> _createLinkCode({int? amount}) async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('createTelegramLinkCode')
        .call({'phone': widget.phone, if (amount != null) 'amount': amount});
    return Map<String, dynamic>.from(res.data as Map? ?? {});
  }

  /// «Ҳамённи тўлдириш»: аввал сумма танланади, кейин бот шу сумма билан очилади.
  Future<void> _topUp() async {
    final amount = await (widget.pickAmount ?? _defaultPick)(
        context, widget.suggestedAmount, widget.maxAmount);
    // Варақ ёпилган (бекор қилинган) — бот очилмайди.
    if (amount == null || !mounted) return;
    if (_lastLinked) {
      setState(() => _notOpened = false);
      final opened = await _openUrl(walletBotDepositUrl(_resolvedBotUsername, amount));
      if (mounted && !opened) setState(() => _notOpened = true);
    } else {
      await _linkAndOpen(amount: amount);
    }
  }

  static Future<int?> _defaultPick(BuildContext context, int? suggested, int max) =>
      showWalletAmountSheet(context, suggested: suggested, max: max);

  /// Охирги кўрилган ҳолат: Telegram боғланганми (build'да ёзилади).
  bool _lastLinked = false;

  Future<void> _linkAndOpen({int? amount}) async {
    setState(() {
      _busy = true;
      _notOpened = false;
    });
    try {
      final data = await _createLinkCode(amount: amount);
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
      if (!opened) setState(() => _notOpened = true);
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
    if (widget.openUrl != null) return widget.openUrl!(url);
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
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
            _lastLinked = linked;

            if (linked) {
              return _linkedBody(context, tgUser);
            }
            return _unlinkedBody(context);
          },
        ),
      ),
    );
  }

  Widget _linkedBody(BuildContext context, String tgUser) {
    final canTap = widget.enabled && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('wlt_tg_title'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.check_circle, color: AvaLight.ok, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tgUser.isNotEmpty
                    ? context.trMsg('wlt_tg_linked_as', params: {'user': tgUser})
                    : context.tr('wlt_tg_linked'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AvaLight.ok,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          context.tr('wlt_tg_deposit_hint'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('wallet-open-bot'),
          onPressed: canTap ? _topUp : null,
          icon: const Icon(Icons.telegram),
          label: Text(context.tr('wlt_topup_btn')),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
        ),
        TextButton(
          onPressed: canTap ? () => _linkAndOpen() : null,
          child: Text(context.tr('wlt_tg_relink')),
        ),
      ],
    );
  }

  Widget _unlinkedBody(BuildContext context) {
    final canTap = widget.enabled && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('wlt_tg_title'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          context.tr('wlt_tg_unlinked_hint'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('wallet-link-bot'),
          onPressed: canTap ? _topUp : null,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onPrimary,
                  ),
                )
              : const Icon(Icons.telegram),
          label: Text(context.tr('wlt_topup_btn')),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
        ),
        if (_notOpened || _code != null) ...[
          const SizedBox(height: 12),
          if (_notOpened)
            Text(
              context.tr('wlt_tg_not_opened'),
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          if (_code != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    context.trMsg('wlt_tg_code', params: {'code': _code!}),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.tr('wlt_copy'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _code!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.tr('wlt_code_copied'))),
                    );
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            if (_botUsername != null && _botUsername!.isNotEmpty)
              Text(
                context.trMsg('wlt_tg_in_bot', params: {'code': _code!}),
                style: const TextStyle(fontSize: 13),
              ),
          ],
        ],
      ],
    );
  }
}
