import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/utils/chatgpt_launcher.dart';
import '../../core/utils/formatters.dart';
import '../profile/screens/profile_screen.dart';
import '../profile/screens/wallet_screen.dart';
import 'models/assistant_status.dart';
import 'screens/assistant_chat_screen.dart';
import 'services/assistant_service.dart';
import 'widgets/assistant_gpt_colors.dart';
import 'widgets/assistant_pro_sheet.dart' show assistantBuyConfirmText;
import '../../core/theme/ava_tokens.dart';

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
/// Тариф (эга қарори, 2026-11-17; аввалги «бир марталик → доимий» бекор): оддий — бепул
/// 10 хабар/кун; AVA AI Plus (чат + нарх қидириш) — 25 000 сўм ТЎЛОВ ПАЙТИДАН 24 СОАТ
/// (ҳамёндан, `assistantBuyPackage` `day` пакети). Фаол бўлса «… гача фаол», тугаса яна «Тўлаш».
/// Дизайн — ChatGPT услуби ([GptColors], Inter).
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
    case _EntryChoice.topUp:
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WalletScreen(phone: phone)),
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

enum _EntryChoice { ava, register, chatGpt, topUp }

/// 24 соатлик Plus нархи — сервер default'и билан бир хил (ҳақиқий нарх
/// статусдан келади; бу фақат статус юкланмагунча кўрсатиш учун).
const _kPassPriceFallback = 25000;

class _EntrySheet extends StatefulWidget {
  const _EntrySheet({required this.registered, required this.chatGptInstalled});

  final bool registered;
  final bool chatGptInstalled;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final _service = AssistantService();
  AssistantStatus? _status;
  bool _paying = false;

  bool get registered => widget.registered;
  bool get chatGptInstalled => widget.chatGptInstalled;

  @override
  void initState() {
    super.initState();
    if (registered) _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final s = await _service.getStatus();
      if (mounted) setState(() => _status = s);
    } catch (_) {}
  }

  AssistantPackage? get _passPkg => _status?.passPackage;

  int get _price => _passPkg?.price ?? _kPassPriceFallback;

  void _snack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  /// Тўлаш: тасдиқ → ҳамёндан ечиш → чатни очиш.
  Future<void> _pay() async {
    if (_paying) return;
    final pkg = _passPkg;
    if (pkg == null) {
      _snack(context.tr('assistant_err_unavailable'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('assistant_pro_sheet_title')),
        content: Text(assistantBuyConfirmText(ctx, pkg)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('assistant_pay')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _paying = true);
    try {
      await _service.buyPackage(pkg.id);
      if (!mounted) return;
      Navigator.pop(context, _EntryChoice.ava);
    } on AssistantException catch (err) {
      if (!mounted) return;
      setState(() => _paying = false);
      if (err.isInsufficientBalance) {
        final bal = (err.details['balance'] as num?)?.toInt();
        _snack(
          bal == null
              ? context.tr('assistant_insufficient')
              : '${context.tr('assistant_insufficient')} (${context.trMsg('assistant_balance', params: {'amount': formatPrice(bal)})})',
          action: SnackBarAction(
            label: context.tr('assistant_topup'),
            onPressed: () {
              if (mounted) Navigator.pop(context, _EntryChoice.topUp);
            },
          ),
        );
      } else {
        _snack(context.tr('assistant_err_unavailable'));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _paying = false);
      _snack(context.tr('assistant_err_unavailable'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    final paid = _status?.pro == true;
    final until = _status?.paidUntil;
    final unlimited = _status?.unlimited == true;
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
                  const SizedBox(height: 10),
                  // 24 соатлик Plus: жумла + кичик тугма (ChatGPT'дек ихчам); фаол бўлса — «… гача фаол».
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          registered && paid && unlimited
                              ? context.tr('assistant_pro_unlimited')
                              : registered && paid && until != null
                                  ? context.trMsg('assistant_pro_until',
                                      params: {'date': formatDateShort(until)})
                                  : context.trMsg('assistant_pass_text',
                                      params: {'price': formatPrice(_price)}),
                          key: const ValueKey('assistant_entry_plan_text'),
                          style: GoogleFonts.inter(
                              fontSize: 13, color: c.text, height: 1.35),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (registered && paid)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AvaLight.okSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_rounded,
                                  size: 14, color: AvaLight.ok),
                              const SizedBox(width: 4),
                              Text(
                                context.tr(unlimited ? 'assistant_paid' : 'assistant_active'),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AvaLight.ok,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (registered)
                        SizedBox(
                          height: 32,
                          child: FilledButton(
                            onPressed: _paying ? null : _pay,
                            style: FilledButton.styleFrom(
                              backgroundColor: c.sendBg,
                              foregroundColor: c.sendFg,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: const StadiumBorder(),
                            ),
                            child: _paying
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: c.sendFg),
                                  )
                                : Text(
                                    context.tr('assistant_pay'),
                                    style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                    ],
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
